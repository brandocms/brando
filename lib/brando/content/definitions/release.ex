defmodule Brando.Content.Definitions.Release do
  @moduledoc """
  The module definitions a release ships in its own `priv/modules`, planned
  against and applied to this environment's database.

      # config/config.exs
      config :brando, Brando.Content.Definitions, release_path: "priv/modules"

  A relative path is in the application's `priv` as the release has it
  (`Application.app_dir/2`). Without `release_path` this is off. With
  `tenancy_mode: :multi`, `{site_key}` in the path is the site's key
  (`"priv/modules/{site_key}"`); a site without that directory has no
  release definitions. Without it, every site's environments are planned
  against the same directory.

  Each definition is compared with what was last applied to this database
  (`Brando.Content.DefinitionApply`), not with the lockfile, which describes
  the database the files were last imported into in development:

    * `update` - the files changed, and the database still equals what was
      last applied
    * `conflict` - the files changed, and the definition was also changed in
      the admin since the last apply (the item says who and when)
    * `noop` - the database already equals the files, or only the admin
      changed it since the last apply
    * a definition with no apply recorded is recorded as applied when the
      database equals the files (an adoption, which planning writes), and is a
      conflict ("never applied from files") when it differs, until the
      operator names it with `replace:`, which also creates again a definition
      deleted here after it was applied. It never overrides a conflict on a
      definition applied here.

  Nothing applies at boot. `plan/1` and `apply/2` return data for the admin
  and other callers; `status/1` and `apply!/2` print a report for an
  operator, and raise when they fail, so `bin/my_app rpc` exits with a
  non-zero status:

      bin/my_app rpc 'Brando.Content.Definitions.Release.status()'
      bin/my_app rpc 'Brando.Content.Definitions.Release.status(format: :line)'
      bin/my_app rpc 'Brando.Content.Definitions.Release.apply!(["acme-hero"], user: 1)'

  In development: `mix brando.modules plan --release` and
  `mix brando.modules apply --release`. See the
  [module definitions guide](module_definitions.md).
  """

  import Kernel, except: [apply: 2]

  alias Brando.Authorization.{Boundary, Engine}
  alias Brando.Content.Definition.{Baselines, Error, Model, Plan}
  alias Brando.Content.{DefinitionApply, Definitions}
  alias Brando.Content.Definitions.Release.Batches
  alias Brando.Tenant
  alias Brando.Tenant.Registry

  @list_path "/admin/config/content/modules"

  @typedoc """
  What `plan/1` returns: the release `version`, the directory it read
  (`path`), the environment (`prefix`), the `plan` itself, its `items` (each
  with the definition's display `name`), counts by action (`counts`), by state
  (`states`) and by `ModuleDiff` class of the updates (`classes`), how many
  items aren't no-ops (`pending`), the entries those affect
  (`affected_entries`) and how many definitions it recorded as applied
  because they equal the files (`adopted`).
  """
  @type report :: %{
          version: String.t(),
          path: String.t(),
          prefix: String.t() | nil,
          plan: Plan.t(),
          items: [map()],
          counts: %{atom() => non_neg_integer()},
          states: %{atom() => non_neg_integer()},
          classes: %{atom() => non_neg_integer()},
          pending: non_neg_integer(),
          affected_entries: non_neg_integer(),
          adopted: non_neg_integer()
        }

  @doc """
  The release's definition directory for the current site, resolved, or nil
  when `release_path` isn't configured. `:path` overrides the configuration.
  """
  def path(opts \\ []) do
    case Keyword.get(opts, :path) || Keyword.get(config(), :release_path) do
      nil ->
        nil

      path ->
        path = String.replace(path, "{site_key}", Tenant.current_site_key() || "")
        if Path.type(path) == :absolute, do: path, else: Application.app_dir(Brando.otp_app(), path)
    end
  end

  @doc "Whether release definitions are configured."
  def enabled?, do: not is_nil(Keyword.get(config(), :release_path))

  defp config, do: Brando.config(Definitions) || []

  @doc """
  The release's version: `RELEASE_VSN`, set in a release, or the
  application's version. `:version` overrides it.
  """
  def version(opts \\ []) do
    Keyword.get_lazy(opts, :version, fn ->
      case System.get_env("RELEASE_VSN") do
        vsn when vsn in [nil, ""] -> to_string(Application.spec(Brando.otp_app(), :vsn) || "dev")
        vsn -> vsn
      end
    end)
  end

  @doc """
  Plans the release's definitions against the current environment's
  database. Returns `{:ok, report}` (see `t:report/0`), `{:ok, :off}` when
  there is no release directory, or `{:error, message}`.

  It records the definitions that equal the files and have no apply
  recorded as applied (`adopt: false` leaves them). Options: `:user` (plans
  as that account, which `apply/2` needs; otherwise as the system, a plan that
  can't be applied), `:references`, `:replace`, `:select` (as for
  `Brando.Content.Definitions.plan/3`), `:path` and `:version`.
  """
  @spec plan(keyword()) :: {:ok, report() | :off} | {:error, String.t()}
  def plan(opts \\ []) do
    path = path(opts)
    if path && File.dir?(path), do: plan_directory(path, opts), else: {:ok, :off}
  end

  defp plan_directory(path, opts) do
    with {:ok, bundle} <- Definitions.read(path),
         {:ok, actor, plan_opts} <- actor(opts),
         {:ok, plan} <- Definitions.plan(bundle, actor, plan_opts ++ plan_options(opts)) do
      adopted = if Keyword.get(opts, :adopt, true), do: adopt(plan, opts), else: 0
      {:ok, report(plan, path, adopted, opts)}
    end
  end

  @doc false
  # Who plans and applies: a superuser as themselves; someone else who may
  # apply release definitions (`authorize/1`) as the system, for them. What
  # they write is code the release ships, or what it replaced, never their
  # own: module code is otherwise a superuser's alone.
  def actor(opts) do
    case Keyword.get(opts, :user) do
      nil ->
        {:ok, :system, [creator: :none]}

      user ->
        with {:ok, user} <- user(user), do: user_actor(user)
    end
  end

  defp user_actor(user) do
    cond do
      Boundary.superuser?(user) -> {:ok, user, []}
      authorize(user) == :ok -> {:ok, :system, [creator: user.id]}
      true -> {:ok, user, []}
    end
  end

  @doc """
  Whether `user` may review and apply the release's module definitions, and
  keep or revert an apply: a superuser, or, with groups authorization, a
  member of a group granted `brando.module_definitions.apply` in this scope.
  Returns `:ok` or `{:error, :forbidden}`.
  """
  @spec authorize(term()) :: :ok | {:error, :forbidden}
  def authorize(nil), do: {:error, :forbidden}
  def authorize(:system), do: :ok

  def authorize(user) do
    cond do
      Boundary.superuser?(user) -> :ok
      Engine.enabled?() and Boundary.authorize(user, :apply, :module_definitions) == :ok -> :ok
      true -> {:error, :forbidden}
    end
  end

  defp user(%Brando.Users.User{id: id}), do: user(id)

  defp user(id) when is_integer(id) do
    case Brando.Repo.get(Brando.Users.User, id) do
      %{active: true, deleted_at: nil} = user -> {:ok, user}
      _ -> {:error, "user #{id} is not an active account"}
    end
  end

  defp user(other), do: {:error, "user: expected an account ID, got #{inspect(other)}"}

  defp plan_options(opts) do
    [baseline: :database]
    |> put_option(:references, opts[:references])
    |> put_option(:replace, opts[:replace])
    |> put_option(:discard, opts[:discard])
    |> put_option(:select, opts[:select])
  end

  defp put_option(options, _key, nil), do: options
  defp put_option(options, key, value), do: Keyword.put(options, key, value)

  defp adopt(plan, opts) do
    Baselines.adopt!(plan, source: :release, release: version(opts))
  end

  defp report(%Plan{} = plan, path, adopted, opts) do
    names = names(plan.bundle)
    items = Enum.map(plan.items, &Map.put(&1, :name, names[&1.uid]))
    pending = Enum.reject(items, &(&1.action == :noop))

    %{
      version: version(opts),
      path: path,
      prefix: Tenant.current_prefix(),
      plan: plan,
      items: items,
      counts: Enum.frequencies_by(items, & &1.action),
      states: Enum.frequencies_by(items, & &1.state),
      classes: pending |> Enum.filter(&(&1.action == :update and &1.class)) |> Enum.frequencies_by(& &1.class),
      pending: length(pending),
      affected_entries: pending |> Enum.map(& &1.entry_count) |> Enum.sum(),
      adopted: adopted
    }
  end

  @doc """
  Applies the release's definitions to the current environment: `:all`, or
  the listed UIDs, each with its module tree (root, children) and the table
  templates the tree uses. `:user` is required; the account's normal
  permissions apply. `replace: [uid]` replaces definitions that were never
  applied from files and differ from them. `:references` maps media and
  content tokens no earlier apply has bound here.

  Refuses, writing nothing, when a selected definition is a conflict or needs
  a migration; `:all` then names them, so they can be left out or resolved.
  Each written definition, and each found equal, is recorded as applied
  with the release version, in the apply's transaction.

  It then waits until each entry that uses a changed module has rendered
  again, on whichever node runs the jobs (`Brando.Content.Definitions.await_refresh/2`):
  `:timeout` in milliseconds (10 minutes) and `:on_progress` are passed on.
  `wait: false` leaves the renders queued and only reports them.
  `:on_applied` is called with `%{report: report, result: result}` once the
  definitions are committed, before the wait.

  Returns `{:ok, %{report: report, result: result, renders: renders, waited?: boolean, run: run, batch_id: batch_id}}`
  with the plan's report, the apply's result (`Brando.Content.Definitions.apply/3`),
  what became of the renders (`t:Brando.Content.Definitions.refresh_result/0`)
  and the run that follows them, or `{:error, message}`.
  """
  @spec apply(:all | [String.t()], keyword()) :: {:ok, map()} | {:error, String.t()}
  def apply(selection, opts) do
    with {:ok, uids} <- selection(selection),
         :ok <- require_user(opts),
         {:ok, %{} = report} <- plan(Keyword.put(opts, :select, uids)) |> on(:off),
         :ok <- applicable(report),
         {:ok, actor, _plan_opts} <- actor(opts),
         {:ok, user} <- user(opts[:user]),
         {{:ok, result}, run} <- track(report, actor, user) do
      wait? = Keyword.get(opts, :wait, true)
      if on_applied = opts[:on_applied], do: on_applied.(%{report: report, result: result})

      renders =
        if wait?,
          do: Definitions.await_refresh(run, Keyword.take(opts, [:timeout, :on_progress, :interval])),
          else: Definitions.refresh_status(run)

      {:ok, %{report: report, result: result, renders: renders, waited?: wait?, run: run, batch_id: result.batch_id}}
    else
      # A definition's save that failed in the transaction names the definition
      {{:error, reason}, _run} -> {:error, Error.describe(reason)}
      error -> error
    end
  end

  # The apply, its rows and its batch in one transaction; the batch confirms
  # the apply before it, and Activity records it as the person's
  defp track(report, actor, user) do
    batch_id = Ecto.UUID.generate()

    Definitions.track_refresh(fn ->
      result =
        Definitions.apply(report.plan, actor,
          source: :release,
          release: report.version,
          batch_id: batch_id,
          in_transaction: fn plan, changes -> record_batch!(report, plan, changes, batch_id, user) end
        )

      with {:ok, _} <- result, %{} = batch <- Batches.get(batch_id) do
        Brando.Activity.setting_changed(:created, batch, Batches.title(batch), user,
          details: %{"release" => report.version, "definitions" => length(batch.definitions["items"] || [])}
        )
      end

      result
    end)
  end

  defp record_batch!(report, _plan, changes, batch_id, user) do
    names = display_names(report.plan.bundle)

    items =
      Enum.map(changes, fn change ->
        %{"uid" => change.uid, "kind" => change.kind, "action" => to_string(change.action), "name" => names[change.uid]}
      end)

    Batches.insert!(
      %{
        batch_id: batch_id,
        source: :release,
        release: report.version,
        run_id: newest_run(),
        definitions: %{"items" => items}
      },
      user.id
    )
  end

  # The run `track/3` started is the newest of the process's runs
  defp newest_run do
    case Enum.reverse(Brando.Content.RenderRun.current()) do
      [run | _] -> run
      [] -> nil
    end
  end

  @doc """
  Keeps the version of `uid` edited here over the release's: the release's
  file is recorded as applied (`:kept`), so it no longer waits, and the edit
  stays. The release's file is out of date until a developer exports the
  module and commits it. Takes `:user` (`authorize/1`), and refuses a
  definition that isn't in conflict. Returns `{:ok, row}` or `{:error, reason}`.
  """
  def keep_here(uid, opts) do
    with :ok <- require_user(opts),
         {:ok, user} <- user(opts[:user]),
         :ok <- authorize(user),
         {:ok, %{} = report} <- plan(Keyword.put(opts, :adopt, false)) |> on(:off),
         {:ok, item} <- conflict_item(report, uid) do
      definition = Enum.find(Model.definitions(report.plan.bundle), &(&1["uid"] == uid))

      references =
        Map.take(
          report.plan.references,
          Map.keys(Brando.Content.Definition.References.declared(%{Model.bundle_key(item.kind) => [definition]}))
        )

      row =
        Brando.Repo.insert!(%DefinitionApply{
          kind: item.kind,
          uid: uid,
          digest: item.after,
          previous_digest: item.before,
          action: :kept,
          source: :release,
          release: report.version,
          references: references,
          batch_id: Ecto.UUID.generate(),
          applied_by_id: user.id,
          applied_at: DateTime.utc_now()
        })

      # The status planned again, and open screens told
      Definitions.changed()
      {:ok, row}
    end
  end

  defp conflict_item(report, uid) do
    case Enum.find(report.items, &(&1.uid == uid)) do
      %{action: :conflict, state: state} = item when state in [:changed_in_both, :never_applied] -> {:ok, item}
      nil -> {:error, "#{uid} is not among the release's definitions"}
      _ -> {:error, "#{uid} is not in conflict"}
    end
  end

  defp selection(:all), do: {:ok, nil}
  defp selection([_ | _] = uids), do: if(Enum.all?(uids, &is_binary/1), do: {:ok, uids}, else: selection(nil))
  defp selection(_), do: {:error, "select :all or a list of definition UIDs"}

  defp require_user(opts) do
    if Keyword.get(opts, :user), do: :ok, else: {:error, "user: is required to apply"}
  end

  defp on({:ok, :off}, :off), do: {:error, "this release has no module definitions (release_path)"}
  defp on(result, _), do: result

  defp applicable(%{plan: plan} = report) do
    if Plan.applicable?(plan) do
      :ok
    else
      blocked =
        report.items
        |> Enum.filter(&(Plan.selected?(plan, &1) and &1.action not in [:create, :update, :noop]))
        |> Enum.map_join("; ", &"#{&1.name} (#{&1.uid}): #{&1.reason}")

      {:error, "nothing was applied; leave out or resolve: " <> blocked}
    end
  end

  ## Commands

  @doc """
  Prints what the release would change in each environment and returns
  `:ok`. Raises when it can't plan, so `rpc` exits with a non-zero status;
  changes waiting are not a failure.

  With tenancy it reports every environment of every site, or those `:site`
  and `:environment` (keys) select. `format: :line` prints one line per
  environment, for a deploy: `3 module changes waiting: https://…/admin/…`.
  Other options as for `plan/1`; `:info` prints a line (default: standard
  output).
  """
  def status(opts \\ []) do
    info = Keyword.get(opts, :info, &IO.puts/1)

    each_target!(opts, fn label ->
      case plan(opts) do
        {:ok, :off} -> info.(prefixed(label, "No module definitions in this release"))
        {:ok, report} -> print_status(report, label, opts, info)
        {:error, message} -> raise "Module definitions#{label && " in " <> label}: #{message}"
      end
    end)
  end

  defp print_status(report, label, opts, info) do
    if Keyword.get(opts, :format) == :line,
      do: info.(prefixed(label, line(report))),
      else: Enum.each(lines(report, label), info)
  end

  @doc """
  Applies the release's definitions in the current environment (or the one
  `:site` and `:environment` select), as `apply/2` does, printing the plan of
  what it applies, the renders' progress and the result. Returns `:ok`;
  raises when it applies nothing, a refresh or a render fails, or the renders
  outlast `:timeout`, so `rpc` exits with a non-zero status.
  """
  def apply!(selection, opts \\ []) do
    # A closed rpc session must not stop the wait: lines it can't print are
    # dropped
    info = printer(Keyword.get(opts, :info, &IO.puts/1))

    opts =
      opts
      |> Keyword.put_new(:on_progress, &progress(&1, info))
      |> Keyword.put(:on_applied, &print_applied(&1, info))

    if Tenant.enabled?() and not (opts[:site] && opts[:environment]),
      do: raise("Module definitions: site: and environment: select the environment to apply to")

    each_target!(opts, fn label ->
      case apply(selection, opts) do
        {:ok, applied} ->
          print_result(applied, info)

        {:error, message} ->
          raise "Module definitions#{label && " in " <> label}: #{message}"
      end
    end)
  end

  defp printer(fun) do
    fn line ->
      try do
        fun.(line)
      catch
        _kind, _reason -> :ok
      end
    end
  end

  # Before the wait: what is committed, whatever becomes of the renders
  defp print_applied(%{report: report, result: result}, info) do
    report.items
    |> Enum.filter(&(Plan.selected?(report.plan, &1) and &1.action != :noop))
    |> Enum.flat_map(&item_lines(report.plan, &1))
    |> Enum.each(info)

    info.("Applied #{length(result.changes)} definition changes from release #{report.version}")
    Enum.each(result.refresh, &(&1.status == :failed && info.("  Refresh failed for #{&1.uid}: #{&1.error}")))
  end

  defp print_result(%{result: result, renders: renders, waited?: waited?}, info) do
    failed = Enum.filter(result.refresh, &(&1.status == :failed))
    print_renders(renders, waited?, info)

    if failed != [],
      do: raise("Module definitions are applied, but refreshing #{Enum.map_join(failed, ", ", & &1.uid)} failed")

    if waited? and (renders.failed != [] or renders.timed_out),
      do: raise("Module definitions are applied, but #{render_problem(renders)}")
  end

  defp progress(%{total: 0}, _info), do: :ok

  defp progress(%{done: done, total: total, failed: failed}, info) do
    failed = if failed > 0, do: " (#{failed} failed)", else: ""
    info.("  Rendering entries: #{done} of #{total} done#{failed}")
  end

  defp print_renders(renders, true, info) do
    if renders.rendered > 0, do: info.("  Rendered #{renders.rendered} entries")
    Enum.each(renders.failed, &info.("  #{job_label(&1)} failed: #{first_line(&1.error)}"))
    Enum.each(renders.pending, &info.("  Still #{&1.state}: #{job_label(&1)}"))
  end

  defp print_renders(%{pending: pending, failed: failed}, false, info) do
    {renders, cascades} = Enum.split_with(pending, &(&1.worker == :render))
    more = if cascades == [], do: "", else: ", and #{length(cascades)} cascade jobs that may queue more"
    if pending != [], do: info.("  #{length(renders)} entry renders are queued for the running server#{more}")
    Enum.each(failed, &info.("  #{job_label(&1)} failed: #{first_line(&1.error)}"))
  end

  defp render_problem(%{timed_out: true, pending: pending}),
    do: "#{length(pending)} render jobs were still waiting when the timeout passed; they stay queued"

  defp render_problem(%{failed: failed}),
    do: "#{length(failed)} entries failed to render; Oban retries them, fix the cause and refresh the module"

  defp job_label(%{worker: worker, schema: schema, entry_id: id, tenant_prefix: prefix}) do
    what = if worker == :cascade, do: "Cascade for", else: "Render of"
    "#{what} #{schema} ##{id}#{prefix && " in " <> prefix}"
  end

  defp first_line(nil), do: "no error recorded"
  defp first_line(error), do: error |> String.split("\n", parts: 2) |> hd()

  defp each_target!(opts, fun) do
    case targets(opts) do
      {:ok, [nil]} ->
        fun.(nil)

      {:ok, targets} ->
        Enum.each(targets, &in_target(&1, fun))

      {:error, message} ->
        raise "Module definitions: #{message}"
    end

    :ok
  end

  defp in_target({site, environment}, fun),
    do: Tenant.with_prefix(Tenant.prefix(site, environment), fn -> fun.("#{site.key}/#{environment.key}") end)

  @doc "Every environment's prefix, or `[nil]` without tenancy."
  def prefixes do
    if Tenant.mode() == :none do
      [nil]
    else
      for site <- Registry.list_sites() |> Enum.sort_by(& &1.id),
          environment <- site.id |> Registry.list_environments() |> Enum.sort_by(& &1.id),
          do: Tenant.prefix(site, environment)
    end
  end

  # The environments to plan: the current one when a caller (the Mix task, the
  # admin) has selected it, every one, or those `:site`/`:environment` pick
  defp targets(opts) do
    cond do
      Tenant.mode() == :none ->
        if opts[:site] || opts[:environment], do: {:error, "site: and environment: need tenancy"}, else: {:ok, [nil]}

      Tenant.current_prefix() && is_nil(opts[:site]) && is_nil(opts[:environment]) ->
        {:ok, [nil]}

      true ->
        tenant_targets(opts)
    end
  end

  defp tenant_targets(opts) do
    sites =
      case opts[:site] do
        nil -> Registry.list_sites() |> Enum.sort_by(& &1.id)
        key -> List.wrap(Registry.get_site_by_key(key))
      end

    targets =
      for site <- sites,
          environment <- site.id |> Registry.list_environments() |> Enum.sort_by(& &1.id),
          opts[:environment] in [nil, environment.key],
          do: {site, environment}

    if targets == [],
      do: {:error, "no environment matches site: #{inspect(opts[:site])}, environment: #{inspect(opts[:environment])}"},
      else: {:ok, targets}
  end

  ## Report text

  @doc "One line for a deploy: how many changes wait, and where to review them."
  def line(%{pending: 0, version: version}), do: "No module changes waiting in release #{version}"

  def line(%{pending: pending} = report),
    do: "#{changes(pending)} waiting in release #{report.version}: #{admin_url()}"

  defp changes(1), do: "1 module change"
  defp changes(count), do: "#{count} module changes"

  @doc "The readable report `status/1` prints, as lines."
  def lines(report, label \\ nil) do
    heading = "Module definitions in release #{report.version}#{label && ", " <> label} (#{report.path})"

    if report.pending == 0 do
      [heading, "  Nothing to apply: the database has every definition in the release" <> adopted(report)]
    else
      [heading, "  " <> summary(report)] ++
        classes(report) ++
        (report.items |> Enum.reject(&(&1.action == :noop)) |> Enum.flat_map(&item_lines(report.plan, &1))) ++
        ["Review: #{admin_url()}", "Apply: " <> apply_hint(report)]
    end
  end

  defp adopted(%{adopted: 0}), do: ""
  defp adopted(%{adopted: count}), do: "; #{count} recorded as applied"

  defp summary(report) do
    counts = report.counts
    never = Map.get(report.states, :never_applied, 0)

    [
      {Map.get(counts, :update, 0), "update", "updates"},
      {Map.get(counts, :create, 0), "new", "new"},
      {Map.get(counts, :conflict, 0) - never, "conflict", "conflicts"},
      {never, "never applied", "never applied"},
      {Map.get(counts, :migration_required, 0), "needs a migration", "need a migration"},
      {report.affected_entries, "entry affected", "entries affected"}
    ]
    |> Enum.reject(fn {count, _, _} -> count == 0 end)
    |> Enum.map_join(" · ", fn
      {1, one, _} -> "1 #{one}"
      {count, _, many} -> "#{count} #{many}"
    end)
  end

  defp classes(%{classes: classes}) when map_size(classes) == 0, do: []

  defp classes(%{classes: classes}) do
    order = [:metadata, :render, :compatible, :destructive]

    text =
      classes
      |> Enum.sort_by(fn {class, _} -> Enum.find_index(order, &(&1 == class)) || 99 end)
      |> Enum.map_join(" · ", fn {class, count} -> "#{count} #{class}" end)

    ["  Updates by kind: " <> text]
  end

  # An update that leaves values in blocks is followed by the command that
  # resolves them
  defp item_lines(plan, item) do
    case Plan.resolve_command(plan, item) do
      nil -> [item_line(item)]
      command -> [item_line(item), "    resolve: " <> command]
    end
  end

  defp item_line(item) do
    detail =
      case item do
        %{action: :update, removes: %{}} -> Plan.removal_text(item)
        %{action: :update, class: class} -> "#{class || "update"}; #{item.entry_count} entries"
        %{action: :create} -> "new"
        %{state: :never_applied} -> item.reason <> " (replace: [#{inspect(item.uid)}])"
        %{action: :conflict} -> conflict_detail(item)
        _ -> item.reason
      end

    "  #{item.action} #{item.kind} #{item.name} (#{item.uid}): #{detail}"
  end

  defp conflict_detail(item) do
    edited =
      case item.edited do
        %{at: at, by: by} -> "changed in the admin#{by_name(by)} at #{stamp(at)}"
        _ -> item.reason
      end

    applied =
      case item.applied do
        %{at: at, by: by, release: release} ->
          "; last applied#{release && " from release " <> release}#{by_name(by)} at #{stamp(at)}"

        _ ->
          ""
      end

    edited <> applied
  end

  defp by_name(%{name: name}) when is_binary(name), do: " by " <> name
  defp by_name(_), do: ""

  defp stamp(%DateTime{} = at), do: at |> DateTime.truncate(:second) |> Calendar.strftime("%Y-%m-%d %H:%M UTC")
  defp stamp(%NaiveDateTime{} = at), do: at |> NaiveDateTime.truncate(:second) |> Calendar.strftime("%Y-%m-%d %H:%M")
  defp stamp(other), do: to_string(other)

  defp apply_hint(report) do
    uids =
      report.items
      |> Enum.filter(&(&1.action in [:create, :update]))
      |> Enum.map(& &1.uid)

    case uids do
      [] -> "resolve the conflicts above first"
      uids -> "Brando.Content.Definitions.Release.apply!(#{inspect(uids)}, user: ID)"
    end
  end

  @doc "The Block modules list in the admin, as a full URL."
  def admin_url do
    Brando.endpoint().url() <> @list_path
  rescue
    _ -> @list_path
  end

  defp prefixed(nil, text), do: text
  defp prefixed(label, text), do: "#{label}: #{text}"

  # As the review screen names them: namespace › name
  defp display_names(bundle) do
    language = to_string(Brando.config(:default_admin_language) || "en")

    Map.new(Model.definitions(bundle), fn definition ->
      namespace = definition["namespace"] && name(%{"name" => definition["namespace"], "uid" => nil}, language)
      title = name(definition, language)
      {definition["uid"], if(namespace in [nil, ""], do: title, else: "#{namespace} › #{title}")}
    end)
  end

  # How the admin names definitions: in the admin language, a child after
  # its parent
  defp names(bundle) do
    language = to_string(Brando.config(:default_admin_language) || "en")
    definitions = Model.definitions(bundle)
    own = Map.new(definitions, &{&1["uid"], name(&1, language)})
    parents = for module <- bundle["modules"], child <- module["children"], into: %{}, do: {child, module["uid"]}

    Map.new(own, fn {uid, name} ->
      case parents[uid] do
        nil -> {uid, name}
        parent -> {uid, "#{own[parent]} › #{name}"}
      end
    end)
  end

  defp name(definition, language) do
    case definition["name"] do
      %{^language => name} when name not in [nil, ""] -> name
      %{"en" => name} when name not in [nil, ""] -> name
      name when is_binary(name) and name != "" -> name
      _ -> definition["uid"]
    end
  end
end
