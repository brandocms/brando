if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Brando.Igniter.UpgradeOrder do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    @moduledoc false
    # The steps `mix brando.migrate55` prints after the source upgrade, in the
    # order guides/migrating_from_053.md gives them.
    #
    # A site whose Blueprint snapshots predate Brando's blocks conversion
    # (`brando_103` to `brando_108`) follows the guide's "Legacy snapshots"
    # order: Brando's own migrations run first, and the Blueprint migrations
    # are generated with `--reconcile` against the database they produced.
    # Otherwise the Blueprint migrations are generated before anything runs.

    alias Rewrite.Source

    # The last Brando migration before the blocks conversion.
    @last_pre_blocks_migration 102
    @migrations_glob "priv/repo/migrations/*_brando_*.exs"
    @snapshots_glob "priv/blueprints/snapshots/*/*.snapshot"

    @doc """
    The "Continue in this order" block, and the igniter with the migration and
    snapshot files it read included.
    """
    @spec notice(Igniter.t()) :: {Igniter.t(), String.t()}
    def notice(igniter) do
      {igniter, reasons} = legacy_reasons(igniter)
      {igniter, steps(reasons)}
    end

    @doc """
    Why the application counts as having legacy snapshots: the newest copied
    Brando migration, when it predates the blocks conversion, and the latest
    snapshots that still declare a Villain field. Empty when neither holds.
    """
    @spec legacy_reasons(Igniter.t()) :: {Igniter.t(), [String.t()]}
    def legacy_reasons(igniter) do
      igniter =
        igniter
        |> Igniter.include_glob(@migrations_glob)
        |> Igniter.include_glob(@snapshots_glob)

      sources = Rewrite.sources(igniter.rewrite)
      paths = Enum.map(sources, &Source.get(&1, :path))

      migration =
        paths
        |> Enum.filter(&(Path.dirname(&1) == "priv/repo/migrations"))
        |> Enum.flat_map(&brando_number/1)
        |> Enum.max(fn -> nil end)

      migration_reason =
        if migration && migration <= @last_pre_blocks_migration,
          do: ["the newest Brando migration in priv/repo/migrations is brando_#{migration}"],
          else: []

      snapshot_reasons =
        sources
        |> Enum.filter(&snapshot?(Source.get(&1, :path)))
        |> Enum.group_by(&Path.dirname(Source.get(&1, :path)))
        |> Enum.map(fn {_directory, snapshots} -> Enum.max_by(snapshots, &Source.get(&1, :path)) end)
        |> Enum.filter(&villain_snapshot?/1)
        |> Enum.map(&(&1 |> Source.get(:path) |> Path.dirname() |> Path.basename()))
        |> Enum.sort()
        |> case do
          [] -> []
          [one] -> ["the latest snapshot in priv/blueprints/snapshots/#{one} has a Villain field"]
          many -> ["the latest snapshots of #{Enum.join(many, ", ")} in priv/blueprints/snapshots have Villain fields"]
        end

      {igniter, migration_reason ++ snapshot_reasons}
    end

    defp brando_number(path) do
      case Regex.run(~r/^\d+_brando_(\d+)_/, Path.basename(path)) do
        [_, number] -> [String.to_integer(number)]
        nil -> []
      end
    end

    defp snapshot?(path) do
      String.starts_with?(path, "priv/blueprints/snapshots/") and Path.extname(path) == ".snapshot"
    end

    # A snapshot written before the conversion lists its attributes, a Villain
    # field among them as `type: :villain`. Later formats keep a storage schema.
    defp villain_snapshot?(source) do
      case decode(Source.get(source, :content)) do
        %{attributes: attributes} when is_list(attributes) ->
          Enum.any?(attributes, &match?(%{type: :villain}, &1))

        _other ->
          false
      end
    end

    defp decode(binary) do
      Plug.Crypto.non_executable_binary_to_term(binary)
    rescue
      _error in [ArgumentError, ErlangError] -> nil
    end

    defp steps([]) do
      """
      Continue in this order:

        1. Review the complete Igniter diff, then run `mix format` and
           `mix compile --warnings-as-errors`.
      #{florist_step(2)}
        3. Run `mix brando.gen.migrations` to copy Brando's missing Ecto
           migrations, then `mix brando.migrations.check` against the database
           you will migrate: it lists copies made earlier that have not run and
           differ from Brando's templates.
        4. Run `mix brando.gen.blueprint_migration --all` to plan the migrations
           of every application Blueprint (an existing table without a snapshot
           gets a `--rebaseline` instead; see the guide).
        5. Review every generated `up/0` and `down/0`, test rollback/forward,
           and commit the source, migrations, and snapshots together.
        6. Only after that review, run `mix brando.migrate`, followed by
           `mix brando.migrate --tenants` when the application has named
           environments.
      #{derived_data_steps(7)}

      #{database_task(8)}
      """
    end

    defp steps(reasons) do
      """
      Continue in this order. This application's Blueprint snapshots predate
      Brando's blocks conversion (#{Enum.join(reasons, "; ")}), so the
      Blueprint migrations are generated against a database Brando's own
      migrations have converted, as "Legacy snapshots" in
      guides/migrating_from_053.md describes:

        1. Review the complete Igniter diff, then run `mix format` and
           `mix compile --warnings-as-errors`.
      #{florist_step(2)}
        3. Run `mix brando.gen.migrations` to copy Brando's missing Ecto
           migrations, then `mix brando.migrations.check` against the database
           you will migrate: it lists copies made earlier that have not run and
           differ from Brando's templates.
        4. Run `mix brando.migrate` on a copy of production. This runs Brando's
           migrations, the Villain-to-blocks conversion among them; the
           Blueprint migrations come later.
        5. Run `mix brando.check.legacy_conversion`. It names every Villain
           block, var, ref or fragment the conversion lost, and every picture,
           gallery image or video a ref lost, and exits with status 1 while
           anything is missing. `mix brando.repair.legacy_media` puts back
           lost media from the Villain columns.
        6. Run `mix brando.gen.blueprint_migration --all --reconcile` (with
           `--dry-run` first) against that migrated database. It keeps the
           Villain columns and the storage that holds data, and guards what
           already exists. With named environments `--reconcile` is refused:
           edit the generated migrations by hand as the guide describes.
        7. Review every generated `up/0` and `down/0`, roll back and forward
           once, check that a second `--all --dry-run` proposes nothing, and
           commit the source, migrations, and snapshots together.
        8. Run `mix brando.migrate` again for the Blueprint migrations,
           followed by `mix brando.migrate --tenants` when the application has
           named environments.
      #{derived_data_steps(9)}

      #{database_task(10)}
      """
    end

    # The database phase, steps 3 to `last`, as one rerunnable task.
    defp database_task(last) do
      """
      Without named environments, `mix brando.upgrade.database` walks steps 3
      to #{last} for you: it runs each in turn, asks before changing the
      database, stops at every review point, and rebuilds the search index at
      the end. Rerun it after each stop until it says the database phase is
      done; `--dry-run` shows the plan.\
      """
    end

    defp florist_step(number) do
      """
        #{number}. If `florist.config.exs` was created, set its required password
           environment variables and complete the deployment review in the
           migration guide before running Florist.\
      """
    end

    defp derived_data_steps(first) do
      """
        #{first}. After the database migration, run `mix brando.entries.resave`,
           `mix brando.identifiers.sync` and `mix brando.images.adopt` (try it
           with `--dry-run` first), which records the config each image whose
           files already match was made with.
        #{first + 1}. Run `mix brando.check.image_texts` to find module, container and
           menu templates that print an image's alt text, title or credits
           without the `i18n` filter. Templates live in the database, so this
           source migration cannot see them.
        #{first + 2}. Run `mix brando.gettext.reconcile` (with `--dry-run` first). It
           extracts, merges each Gettext backend's existing locales, fills
           empty translations from sibling catalogs, deletes the 0.53
           `_naming`/`_forms`/`_listings` catalogs the merge empties, and
           lists per Blueprint domain the translations kept and dropped.\
      """
    end
  end
else
  defmodule Mix.Brando.Igniter.UpgradeOrder do
    @moduledoc false
    # Revisit this source when the optional dependency becomes available.
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)
  end
end
