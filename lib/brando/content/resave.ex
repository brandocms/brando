defmodule Brando.Content.Resave do
  @moduledoc """
  Renders every entry's blocks again and stores the result, as an editor's
  save would: what `mix brando.entries.resave` runs, callable from a release.

  On a server, with the release running, run it on the running node. Any
  release can, whatever its `ReleaseTasks` holds:

      bin/my_app rpc "Brando.Content.Resave.run()"

  or, from a `ReleaseTasks` generated with `resave_entries/1`,
  `bin/my_app rpc "MyApp.ReleaseTasks.resave_entries()"`. It then empties
  that node's query cache and reloads its caches itself (see `run/1` for
  what that covers with tenancy). With the release stopped, `eval` starts the
  application in a VM of its own, without its web server and without Oban's
  queues (see `run/1`), re-saves, and says how to empty the caches of a
  server started meanwhile:

      bin/my_app eval "MyApp.ReleaseTasks.resave_entries()"

  `MyApp.ReleaseTasks.resave_entries/1` passes its options here; it can also
  be called as it is, `Brando.Content.Resave.run(otp_app: :my_app)`.

  With tenancy (`:single` or `:multi`), the entries are in each environment's
  schema: it re-saves them in every environment of every site, each under its
  own prefix and outside any admin scope, and names each environment as it
  goes. Without tenancy it re-saves the entries in the application's own
  tables.
  """

  alias Brando.Authorization.Boundary
  alias Brando.Content.Blocks
  alias IO.ANSI

  import Ecto.Query, only: [from: 2]

  @options ~w(blueprint site environment otp_app reload_caches confirm info)a

  # What other entries embed: re-saved first, each evicted from the query
  # cache once stored, so what embeds it renders its new HTML
  @embedded Brando.Pages.Fragment

  @typedoc """
  Options for `run/1`:

    * `:blueprint` - one Blueprint to re-save, a module or its name as a
      string. Without it, every Blueprint with an identifier, fragments first
      and pages last.
    * `:site` - with tenancy, only this site's environments (its key).
    * `:environment` - with tenancy, only the environment with this key, in
      each site (or in `:site`'s).
    * `:otp_app` - the application to start when it is not running. Defaults
      to `config :brando, otp_app:`.
    * `:reload_caches` - whether to reload this node's caches when done.
      Defaults to true when the application was running already (`rpc`), and
      to false when `run/1` started it (`eval`): a node of its own has no
      server's caches to reload, and it says what to do instead.
    * `:confirm` - called with the plan (`%{blueprints: …, environments: …}`)
      once it has been printed, when there is no `:blueprint`; re-saves only
      when it returns true. Defaults to going ahead.
    * `:info` - prints one line of the report, a string or an `IO.ANSI` list.
      Defaults to standard output.
  """
  @type option ::
          {:blueprint, module() | String.t()}
          | {:site, String.t()}
          | {:environment, String.t()}
          | {:otp_app, atom()}
          | {:reload_caches, boolean()}
          | {:confirm, (map() -> boolean())}
          | {:info, (IO.ANSI.ansidata() -> any())}

  @doc """
  Re-saves the entries (see the moduledoc), printing what it does, and
  returns `{:ok, count}` with the number re-saved, `{:ok, :declined}` when
  `:confirm` said no, or `{:error, message}` before anything is done: for an
  option it does not take, or a Blueprint, site or environment that does not
  exist. It prints the message too, unless the caller passed `:info` (the
  Mix task reports it itself).

  The report is written to the caller's standard output, which over `rpc` is
  the operator's session. A line that cannot be written (the session was
  closed) is dropped, and the run goes on. The caches are reloaded
  (`:reload_caches`) after a failure too.

  Each environment's pass first refreshes that environment's render inputs
  on this node, whatever the node has heard: the identity, globals and menus
  entries render with, and the cached lists of modules, containers,
  palettes and fragments (`Brando.Cache.refresh_render_inputs/1`). Fragments
  are re-saved first, each after the fragments its blocks embed, and each is
  evicted from the query cache once stored, so the entries that embed it
  render its new HTML.

  When done, with `:reload_caches` it empties this
  node's whole query cache (every site's and environment's pages,
  fragments, …) and rebuilds the site caches (identity, SEO, globals,
  palettes, menus) of the context it runs in, as Configuration → Cache →
  Empty all caches does. With tenancy that context is outside every site,
  so no environment's site caches are rebuilt then: each environment's
  identity, globals and menus were rebuilt as its pass began, and its SEO
  and palettes are left as they were (re-saving does not change them).
  Other nodes keep their caches.

  ## Started by `eval`

  When the application is not running and this node is not distributed, as
  in a release's `eval`, it starts it in this VM, beside a
  server that may be running: with the endpoint's `server: false`, so it
  serves nothing, and Oban in `testing: :manual` (Brando's instance, and an
  `Oban` configured under the application's own name), so it runs no queues
  and no cron or other plugins: jobs it inserts wait for the server's
  queues. `Brando.Tenant.ServedHosts` starts with its `file` unset, so it
  writes no hosts file for the reverse proxy, and GitHub's webhook
  addresses are not fetched. A release's `eval` VM runs without
  distribution, so it joins no cluster and its `Phoenix.PubSub` broadcasts
  (`Brando.CacheSync`) stay in it, unless the application uses an adapter
  such as `phoenix_pubsub_redis`: then the serving nodes hear that each
  re-saved fragment changed, which is true.

  Everything else in the application's supervision tree starts as it does
  at boot: its repos, caches and PubSub, and any process of its own that
  acts by itself once started (scheduled work outside Oban, say), which the
  application has to keep from running in a second VM itself.

  On a distributed node whose application is not started (an `rpc` to a
  release still booting, or an `otp_app:` naming another application), it
  changes nothing and returns `{:error, message}`, as it does for an
  application it cannot load.
  """
  @spec run([option]) :: {:ok, non_neg_integer() | :declined} | {:error, String.t()}
  def run(opts \\ []) do
    info = printer(opts[:info] || (&IO.puts(ANSI.format(&1))))
    opts |> resave(info) |> report_error(opts, info)
  end

  defp resave(opts, info) do
    with :ok <- check_options(opts),
         {:ok, started_here?} <- start(opts[:otp_app] || Brando.otp_app()),
         {:ok, environments} <- environments(opts),
         {:ok, blueprints, listed?} <- blueprints(opts[:blueprint]) do
      plan = %{blueprints: blueprints, environments: environments}

      if go_ahead?(plan, listed?, opts[:confirm], info) do
        try do
          {:ok, resave_in(plan, info)}
        after
          caches(Keyword.get(opts, :reload_caches, not started_here?), started_here?, info)
        end
      else
        info.("Nothing was done.")
        {:ok, :declined}
      end
    end
  end

  defp report_error({:error, message} = error, opts, info) do
    if is_nil(opts[:info]), do: info.([:red, "Nothing was done: " <> message])
    error
  end

  defp report_error(result, _opts, _info), do: result

  defp check_options(opts) do
    cond do
      not Keyword.keyword?(opts) ->
        {:error, "the options must be a keyword list, got: #{inspect(opts)}"}

      (unknown = Keyword.keys(opts) -- @options) != [] ->
        {:error,
         "unknown option #{Enum.map_join(Enum.uniq(unknown), ", ", &"#{&1}:")}. " <>
           "It takes: #{Enum.map_join(@options, ", ", &"#{&1}:")}"}

      key = Enum.find([:site, :environment], &(not (is_nil(opts[&1]) or is_binary(opts[&1])))) ->
        {:error, "#{key}: must be a key, as a string, got: #{inspect(opts[key])}"}

      true ->
        :ok
    end
  end

  # A line the caller's output cannot take (an `rpc` session that closed:
  # its group leader is gone) is dropped rather than stopping the run
  defp printer(fun) do
    fn line ->
      try do
        fun.(line)
      catch
        _kind, _reason -> :ok
      end
    end
  end

  @doc false
  # How `run/1` treats the application, from whether this node is distributed
  # and whether the application is started: running (`rpc`), to start here
  # (`eval`, whose VM is not distributed), or `:not_started` on a node that
  # is (a release still booting, or another application's node), which it
  # must leave alone
  @spec start_mode(boolean(), boolean()) :: :running | :eval | :not_started
  def start_mode(_distributed?, true), do: :running
  def start_mode(false, false), do: :eval
  def start_mode(true, false), do: :not_started

  # `{:ok, started_here?}` (see "Started by `eval`" in `run/1`)
  defp start(nil), do: {:ok, false}

  defp start(app) do
    case start_mode(Node.alive?(), List.keymember?(Application.started_applications(), app, 0)) do
      :running ->
        {:ok, false}

      :not_started ->
        {:error,
         "#{inspect(app)} is not started on this node: it is still starting, or it is not this node's " <>
           "application (otp_app:). Try again once it has started."}

      :eval ->
        with :ok <- load(app) do
          start_here(app)
          {:ok, true}
        end
    end
  end

  defp load(app) do
    case Application.load(app) do
      :ok -> :ok
      {:error, {:already_loaded, ^app}} -> :ok
      {:error, reason} -> {:error, "cannot load the application #{inspect(app)}: #{inspect(reason)}"}
    end
  end

  defp start_here(app) do
    _ = Application.load(:brando)
    oban = Application.get_env(:brando, Oban) || Brando.Supervisor.oban_config()
    Application.put_env(:brando, Oban, Keyword.put(oban, :testing, :manual))

    with app_oban when is_list(app_oban) <- Application.get_env(app, Oban),
         do: Application.put_env(app, Oban, Keyword.put(app_oban, :testing, :manual))

    with endpoint when not is_nil(endpoint) <- Brando.endpoint(),
         config when is_list(config) <- Application.get_env(app, endpoint) do
      Application.put_env(app, endpoint, Keyword.put(config, :server, false))
    end

    # The serving node's: the hosts file the reverse proxy reads, and the
    # addresses its GitHub webhooks come from
    served_hosts = Application.get_env(:brando, Brando.Tenant.ServedHosts, [])
    Application.put_env(:brando, Brando.Tenant.ServedHosts, Keyword.delete(served_hosts, :file))
    markdown_sources = Application.get_env(:brando, :markdown_sources, [])
    Application.put_env(:brando, :markdown_sources, Keyword.put(markdown_sources, :github_meta_url, nil))

    # Its boot log (and SQL, in development) would run through the report
    Logger.configure(level: :error)
    {:ok, _} = Application.ensure_all_started(app)
    Logger.configure(level: :error)
  end

  # `[nil]` without tenancy: the application's own tables. With tenancy, every
  # `{site, environment}`, narrowed by `:site` and `:environment`.
  defp environments(opts) do
    case Brando.Tenant.mode() do
      :none ->
        if opts[:site] || opts[:environment],
          do: {:error, "--site and --environment need tenancy, which is off"},
          else: {:ok, [nil]}

      _tenancy ->
        with {:ok, sites} <- sites(opts[:site]), do: site_environments(sites, opts)
    end
  end

  defp site_environments(sites, opts) do
    sites
    |> Enum.flat_map(fn site -> site.environments |> Enum.sort_by(& &1.id) |> Enum.map(&{site, &1}) end)
    |> Enum.filter(fn {_site, environment} -> opts[:environment] in [nil, environment.key] end)
    |> case do
      [] -> {:error, "no environment matches #{describe_filter(opts)}"}
      environments -> {:ok, environments}
    end
  end

  defp sites(nil), do: {:ok, Enum.sort_by(Brando.Tenant.Registry.list_sites(), & &1.id)}

  defp sites(key) do
    case Brando.Tenant.Registry.get_site_by_key(key) do
      nil -> {:error, "no site has the key #{inspect(key)}"}
      site -> {:ok, [site]}
    end
  end

  defp describe_filter(opts) do
    [site: opts[:site], environment: opts[:environment]]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
    |> Enum.map_join(" and ", fn {key, value} -> "--#{key} #{value}" end)
    |> case do
      "" -> "(there are none)"
      filter -> filter
    end
  end

  # The Blueprints to re-save, and whether they are listed before asking: all
  # of them are, one named Blueprint is not.
  defp blueprints(nil) do
    blueprints =
      ([@embedded] ++ Brando.Blueprint.list_blueprints() ++ [Brando.Pages.Page])
      |> Enum.reject(&Brando.Blueprint.embedded?/1)

    {:ok, blueprints, true}
  end

  defp blueprints(name) when is_binary(name), do: blueprints(Module.concat([name]))

  defp blueprints(blueprint) when is_atom(blueprint) do
    cond do
      not (Code.ensure_loaded?(blueprint) and function_exported?(blueprint, :__has_identifier__, 0)) ->
        {:error, "#{inspect(blueprint)} is not a Blueprint"}

      # No table and no context list function of its own
      Brando.Blueprint.embedded?(blueprint) ->
        {:error,
         """
         #{inspect(blueprint)} declares `data_layer :embedded`.

         Embedded Blueprints have no table and no context list function of their own —
         they are re-saved with the entry that embeds them.\
         """}

      true ->
        {:ok, [blueprint], false}
    end
  end

  # One named Blueprint goes ahead without asking, as it always has: all of
  # them are listed first, and asked about
  defp go_ahead?(_plan, false, _confirm, _info), do: true

  defp go_ahead?(plan, true, confirm, info) do
    show_plan(plan, info)
    if confirm, do: confirm.(plan), else: true
  end

  defp show_plan(%{blueprints: blueprints, environments: environments}, info) do
    info.([:yellow, "\n==> Blueprint schemas that will be resaved:\n\n"])
    for blueprint <- blueprints, do: info.([:green, "    * #{inspect(blueprint, pretty: true)}"])

    if environments != [nil] do
      info.([:yellow, "\n==> In these environments:\n\n"])
      for {site, environment} <- environments, do: info.([:green, "    * " <> name(site, environment)])
    end
  end

  defp resave_in(%{blueprints: blueprints, environments: environments}, info) do
    blueprints = Enum.filter(blueprints, & &1.__has_identifier__())

    # The hosts the entries' URLs start with
    if environments != [nil], do: Brando.Cache.refresh_render_inputs(registry: true)

    count =
      environments
      |> Enum.map(fn target -> in_environment(target, info, fn -> resave_here(blueprints, info) end) end)
      |> Enum.sum()

    info.("\nResaved #{count} #{if count == 1, do: "entry", else: "entries"}#{where(environments)}.")
    info.([:green, "\n==> Done.\n"])
    count
  end

  # Reloaded on the node it runs on, which is the server's over `rpc`. Each
  # node has its own caches.
  defp caches(true, _started_here?, info) do
    :ok = Brando.Cache.reload_all()

    info.(
      "Emptied this node's query cache and reloaded its site caches. " <>
        "Other nodes keep theirs: empty them in their admin, or restart them."
    )
  end

  defp caches(false, started_here?, info) do
    info.(
      "Servers that were already running keep serving what they cached before. " <>
        "Restart them, or empty their caches in the admin under Configuration → Cache → Empty all caches."
    )

    # Started for this, from `eval`: the server is another node
    if started_here? do
      info.(
        "From the release: bin/#{Brando.otp_app()} rpc \"Brando.Cache.reload_all()\", " <>
          "or with Florist, florist <env> cache:clear."
      )
    end
  end

  # The entries and images of the environment it is in, from its render
  # inputs as they are now: this node may not have heard of what changed them
  defp resave_here(blueprints, info) do
    :ok = Brando.Cache.refresh_render_inputs()
    count = Enum.sum_by(blueprints, &resave_entries(&1, info))
    report_stale_config_targets(info)
    count
  end

  defp where([nil]), do: ""
  defp where([_one]), do: " in 1 environment"
  defp where(environments), do: " in #{length(environments)} environments"

  defp in_environment(nil, _info, fun), do: fun.()

  defp in_environment({site, environment}, info, fun) do
    info.([:yellow, "\n==> #{name(site, environment)}\n"])

    Boundary.with_scope(nil, fn ->
      Brando.Tenant.with_prefix(Brando.Tenant.prefix(site, environment), fun)
    end)
  end

  defp name(site, environment), do: "#{site.name} (#{site.key}) → #{environment.name} (#{environment.key})"

  # Rendering falls back to the default image config for images whose
  # config target no longer resolves; one line per target says how many.
  defp report_stale_config_targets(info) do
    stale = Brando.Images.Processing.stale_config_targets()

    if stale != %{} do
      info.([:yellow, "\n==> Images with a config target that no longer resolves:\n"])

      for {target, count} <- Enum.sort(stale) do
        info.("    * " <> Brando.Images.ConfigResolver.stale_target_message(target, count))
      end
    end
  end

  defp resave_entries(blueprint, info) do
    context = blueprint.__modules__().context
    singular = blueprint.__naming__().singular
    plural = blueprint.__naming__().plural
    preloads = Brando.Blueprint.preloads_for(blueprint)
    {:ok, entries} = apply(context, :"list_#{plural}", [%{order: "asc id", preload: preloads}])

    info.([:green, "\n==> Resaving #{singular} entries\n"])
    write = printer(&IO.write(ANSI.format(&1)))

    entries
    |> in_render_order(blueprint)
    |> Enum.count(&resave_entry(blueprint, &1, singular, write))
  end

  defp resave_entry(blueprint, entry, singular, write) do
    title = blueprint.__identifier__(entry, skip_cover: true).title

    # IO.ANSI.format/1 drops the colours when stdout is not a terminal.
    write.([
      "* [",
      :blue,
      "#{singular}",
      :reset,
      ":",
      :blue,
      "#{entry.id}",
      :reset,
      "] → ",
      :blue,
      title,
      :reset,
      " ... "
    ])

    # Loaded again as it is now, and stored only over that: an editor may
    # have saved it since the list was read, or save it while it renders
    keep_updated_at = &Ecto.Changeset.force_change(&1, :updated_at, &1.data.updated_at)

    case Blocks.render_and_store(blueprint, entry.id, prepare: keep_updated_at, force: true) do
      {:ok, stored} ->
        if blueprint == @embedded, do: Brando.Cache.Query.evict({:ok, stored})
        write.([:green, "done!\n"])
        true

      {:error, _} ->
        write.([:red, "failed!\n"])
        false
    end
  end

  # Fragments after the fragments their blocks embed, in id order otherwise
  # (and for those in a cycle)
  defp in_render_order(entries, @embedded) do
    ids = MapSet.new(entries, & &1.id)
    embeds = fragment_embeds(ids)
    order(entries, embeds, MapSet.new(), [])
  end

  defp in_render_order(entries, _blueprint), do: entries

  # %{fragment id => ids of the fragments it embeds}
  defp fragment_embeds(ids) do
    from(b in Brando.Content.Block, where: b.fragment_id in ^MapSet.to_list(ids), distinct: true, select: b.fragment_id)
    |> Brando.Repo.all()
    |> Enum.reduce(%{}, fn embedded_id, embeds ->
      embedded_id
      |> Blocks.list_block_ids_using_fragment()
      |> Blocks.list_root_block_ids_by_source()
      |> Blocks.list_entry_ids_for_root_blocks_by_source()
      |> Map.get(@embedded, [])
      |> Enum.filter(&(&1 != embedded_id and MapSet.member?(ids, &1)))
      |> Enum.reduce(embeds, &Map.update(&2, &1, [embedded_id], fn embedded -> [embedded_id | embedded] end))
    end)
  end

  defp order([], _embeds, _done, ordered), do: Enum.reverse(ordered)

  defp order(pending, embeds, done, ordered) do
    case Enum.split_with(pending, fn entry -> Enum.all?(Map.get(embeds, entry.id, []), &MapSet.member?(done, &1)) end) do
      # A cycle: the rest in id order
      {[], rest} -> Enum.reverse(ordered, rest)
      {ready, rest} -> order(rest, embeds, Enum.into(ready, done, & &1.id), Enum.reverse(ready, ordered))
    end
  end
end
