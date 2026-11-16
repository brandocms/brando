defmodule Mix.Tasks.Brando.Entries.Resave do
  use Mix.Task

  alias IO.ANSI

  @shortdoc "Re-save all entries"

  @moduledoc """
  Re-save all entries

      mix brando.entries.resave
      mix brando.entries.resave --yes

  Re-save entries for specific blueprint

      mix brando.entries.resave MyApp.Projects.Project

  Options:

    * `--yes` (or `--force`) - Skip the confirmation prompt. Without it and
      without a terminal to answer on, the task does nothing and exits
      non-zero.
    * `--site <key>` - With tenancy, only this site's environments.
    * `--environment <key>` - With tenancy, only the environment with this
      key, in each site (or in `--site`'s).

  With tenancy (`:single` or `:multi`), the entries are in each environment's
  schema: the task re-saves them in every environment of every site, each
  under its own prefix and outside any admin scope, and names each
  environment as it goes. Without tenancy it re-saves the entries in the
  application's own tables.

  A server that is already running keeps serving the pages it cached before
  (pages are cached without expiry): restart it, or use Configuration → Cache
  → Empty all caches in its admin. The task says so when it is done.

  """
  @spec run(any) :: no_return
  def run(args) do
    {opts, rest} =
      Mix.Brando.parse_options!(
        "brando.entries.resave",
        args,
        [yes: :boolean, force: :boolean, site: :string, environment: :string],
        aliases: [y: :yes],
        max_positional: 1
      )

    Application.put_env(:logger, :level, :error)

    Mix.Tasks.Run.run([])

    Mix.shell().info("""

    ------------------------------
    % Brando Resave Entries
    ------------------------------
    """)

    environments = environments!(opts)

    case rest do
      [] -> resave_all(opts, environments)
      [blueprint_binary] -> resave_one(blueprint_binary, environments)
    end
  end

  # `[nil]` without tenancy: the application's own tables. With tenancy, every
  # `{site, environment}`, narrowed by `--site` and `--environment`.
  defp environments!(opts) do
    case Brando.Tenant.mode() do
      :none ->
        if opts[:site] || opts[:environment],
          do: Mix.raise("mix brando.entries.resave: --site and --environment need tenancy, which is off"),
          else: [nil]

      _tenancy ->
        sites(opts[:site])
        |> Enum.flat_map(fn site -> site.environments |> Enum.sort_by(& &1.id) |> Enum.map(&{site, &1}) end)
        |> Enum.filter(fn {_site, environment} -> opts[:environment] in [nil, environment.key] end)
        |> case do
          [] -> Mix.raise("mix brando.entries.resave: no environment matches #{describe_filter(opts)}")
          environments -> environments
        end
    end
  end

  defp sites(nil), do: Enum.sort_by(Brando.Tenant.Registry.list_sites(), & &1.id)

  defp sites(key) do
    case Brando.Tenant.Registry.get_site_by_key(key) do
      nil -> Mix.raise("mix brando.entries.resave: no site has the key #{inspect(key)}")
      site -> [site]
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

  defp resave_all(opts, environments) do
    blueprints =
      ([Brando.Pages.Fragment] ++
         Brando.Blueprint.list_blueprints() ++ [Brando.Pages.Page])
      |> Enum.reject(&embedded?/1)

    Mix.shell().info([:yellow, "\n==> Blueprint schemas that will be resaved:\n\n"])

    for blueprint <- blueprints do
      Mix.shell().info([:green, "    * #{inspect(blueprint, pretty: true)}"])
    end

    show_environments(environments)

    if Mix.Brando.confirm?("\n\nProceed?", opts) do
      blueprints |> Enum.filter(& &1.__has_identifier__()) |> resave_in(environments)
    else
      Mix.shell().info("Nothing was done.")
    end
  end

  defp resave_one(blueprint_binary, environments) do
    blueprint_module = Module.concat([blueprint_binary])

    if embedded?(blueprint_module) do
      Mix.raise("""
      #{inspect(blueprint_module)} declares `data_layer :embedded`.

      Embedded Blueprints have no table and no context list function of their own —
      they are re-saved with the entry that embeds them.\
      """)
    end

    if blueprint_module.__has_identifier__(), do: resave_in([blueprint_module], environments)
  end

  defp show_environments([nil]), do: :ok

  defp show_environments(environments) do
    Mix.shell().info([:yellow, "\n==> In these environments:\n\n"])
    for {site, environment} <- environments, do: Mix.shell().info([:green, "    * " <> name(site, environment)])
  end

  defp resave_in(blueprints, environments) do
    count =
      environments
      |> Enum.map(fn target -> in_environment(target, fn -> resave_here(blueprints) end) end)
      |> Enum.sum()

    Mix.shell().info("\nResaved #{count} #{if count == 1, do: "entry", else: "entries"}#{where(environments)}.")
    Mix.shell().info([:green, "\n==> Done.\n"])
    Mix.Brando.running_server_note()
  end

  # The entries and images of the environment the task is in
  defp resave_here(blueprints) do
    count = Enum.sum_by(blueprints, &resave_entries/1)
    report_stale_config_targets()
    count
  end

  defp where([nil]), do: ""
  defp where([_one]), do: " in 1 environment"
  defp where(environments), do: " in #{length(environments)} environments"

  defp in_environment(nil, fun), do: fun.()

  defp in_environment({site, environment}, fun) do
    Mix.shell().info([:yellow, "\n==> #{name(site, environment)}\n"])

    Brando.Authorization.Boundary.with_scope(nil, fn ->
      Brando.Tenant.with_prefix(Brando.Tenant.prefix(site, environment), fun)
    end)
  end

  defp name(site, environment), do: "#{site.name} (#{site.key}) → #{environment.name} (#{environment.key})"

  # Rendering falls back to the default image config for images whose
  # config target no longer resolves; one line per target says how many.
  defp report_stale_config_targets do
    stale = Brando.Images.Processing.stale_config_targets()

    if stale != %{} do
      Mix.shell().info([:yellow, "\n==> Images with a config target that no longer resolves:\n"])

      for {target, count} <- Enum.sort(stale) do
        Mix.shell().info("    * " <> Brando.Images.ConfigResolver.stale_target_message(target, count))
      end
    end
  end

  # Embedded Blueprints live inside their parent's column: no table, no
  # `list_<plural>/1` on any context. Walking them raises UndefinedFunctionError.
  defp embedded?(blueprint_module), do: Brando.Blueprint.embedded?(blueprint_module)

  defp resave_entries(blueprint_module) do
    context = blueprint_module.__modules__().context
    singular = blueprint_module.__naming__().singular
    plural = blueprint_module.__naming__().plural
    preloads = Brando.Blueprint.preloads_for(blueprint_module)
    {:ok, entries} = apply(context, :"list_#{plural}", [%{order: "asc id", preload: preloads}])

    Mix.shell().info([:green, "\n==> Resaving #{singular} entries\n"])

    Enum.count(entries, fn entry ->
      title = blueprint_module.__identifier__(entry, skip_cover: true).title

      # IO.ANSI.format/1 drops the colours when stdout is not a terminal.
      IO.write(
        ANSI.format([
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
      )

      # Loaded again as it is now, and stored only over that: an editor may
      # have saved it since the list was read, or save it while it renders
      keep_updated_at = &Ecto.Changeset.force_change(&1, :updated_at, &1.data.updated_at)

      case Brando.Content.Blocks.render_and_store(blueprint_module, entry.id, prepare: keep_updated_at, force: true) do
        {:ok, _} ->
          IO.write(ANSI.format([:green, "done!\n"]))
          true

        {:error, _} ->
          IO.write(ANSI.format([:red, "failed!\n"]))
          false
      end
    end)
  end
end
