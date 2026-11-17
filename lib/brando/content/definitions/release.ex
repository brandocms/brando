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

  alias Brando.Content.Definition.{Baselines, Plan}
  alias Brando.Content.Definitions
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

  defp actor(opts) do
    case Keyword.get(opts, :user) do
      nil -> {:ok, :system, [creator: :none]}
      user -> with {:ok, user} <- user(user), do: {:ok, user, []}
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

  Returns `{:ok, %{report: report, result: result, renders: renders, waited?: boolean}}`
  with the plan's report, the apply's result (`Brando.Content.Definitions.apply/3`)
  and what became of the renders (`t:Brando.Content.Definitions.refresh_result/0`),
  or `{:error, message}`.
  """
  @spec apply(:all | [String.t()], keyword()) :: {:ok, map()} | {:error, String.t()}
  def apply(selection, opts) do
    with {:ok, uids} <- selection(selection),
         :ok <- require_user(opts),
         {:ok, %{} = report} <- plan(Keyword.put(opts, :select, uids)) |> on(:off),
         :ok <- applicable(report),
         {:ok, user} <- user(opts[:user]),
         {{:ok, result}, run} <- track(report, user) do
      wait? = Keyword.get(opts, :wait, true)

      renders =
        if wait?,
          do: Definitions.await_refresh(run, Keyword.take(opts, [:timeout, :on_progress, :interval])),
          else: Definitions.refresh_status(run)

      {:ok, %{report: report, result: result, renders: renders, waited?: wait?}}
    else
      {{:error, message}, _run} -> {:error, message}
      error -> error
    end
  end

  defp track(report, user),
    do:
      Definitions.track_refresh(fn -> Definitions.apply(report.plan, user, source: :release, release: report.version) end)

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
    info = Keyword.get(opts, :info, &IO.puts/1)
    opts = Keyword.put_new(opts, :on_progress, &progress(&1, info))

    if Tenant.enabled?() and not (opts[:site] && opts[:environment]),
      do: raise("Module definitions: site: and environment: select the environment to apply to")

    each_target!(opts, fn label ->
      case apply(selection, opts) do
        {:ok, %{report: report} = applied} ->
          report.items
          |> Enum.filter(&(Plan.selected?(report.plan, &1) and &1.action != :noop))
          |> Enum.each(&info.(item_line(&1)))

          print_result(applied, info)

        {:error, message} ->
          raise "Module definitions#{label && " in " <> label}: #{message}"
      end
    end)
  end

  defp print_result(%{result: result, report: report, renders: renders, waited?: waited?}, info) do
    info.("Applied #{length(result.changes)} definition changes from release #{report.version}")
    failed = Enum.filter(result.refresh, &(&1.status == :failed))
    Enum.each(failed, &info.("  Refresh failed for #{&1.uid}: #{&1.error}"))
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

  defp print_renders(%{pending: pending}, false, info) do
    if pending != [], do: info.("  #{length(pending)} render jobs are queued for the running server")
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
        (report.items |> Enum.reject(&(&1.action == :noop)) |> Enum.map(&item_line/1)) ++
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

  defp item_line(item) do
    detail =
      case item do
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

  # How the admin names definitions: in the admin language, a child after
  # its parent
  defp names(bundle) do
    language = to_string(Brando.config(:default_admin_language) || "en")
    definitions = bundle["modules"] ++ bundle["table_templates"]
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
