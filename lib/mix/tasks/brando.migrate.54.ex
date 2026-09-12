if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Migrate54 do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task

    alias Mix.Brando.Igniter.SourceUpgrade

    @shortdoc "Migrates application source from Brando 0.53 to 0.54"
    @moduledoc """
    #{@shortdoc}.

    Run this task from a clean, committed worktree after updating the Brando
    dependency. It rewrites legacy Blueprint and LivePreview syntax, preserves
    legacy Meta and JSON-LD path extraction semantics, creates the gettext
    recovery helper, and schedules Igniter's Gettext source upgrade.

    The task changes source files only, and every rewrite matches 0.53 syntax
    only, so rerunning it is safe. An application that already uses 0.54
    syntax is left unchanged. Continue with `mix brando.migrate55` for the
    0.54 to 0.55 changes; the complete ordered workflow is documented in
    `guides/migrating_from_053.md`.
    """

    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{group: :brando}
    end

    def igniter(igniter) do
      igniter
      |> SourceUpgrade.rename_list_villains()
      |> SourceUpgrade.rewrite_blueprints(&SourceUpgrade.upgrade_054_blueprint/1)
      |> SourceUpgrade.rewrite_preview_targets()
      |> SourceUpgrade.configure_repo_module()
      |> SourceUpgrade.rewrite_dockerfiles()
      |> SourceUpgrade.rewrite_font_urls()
      |> SourceUpgrade.copy_gettext_script()
      |> Igniter.add_task("igniter.update_gettext")
      |> add_notices()
      |> add_warnings()
    end

    defp add_notices(igniter) do
      Igniter.add_notice(igniter, """
      Brando 0.54 source migration prepared.

      In addition to the Blueprint and LivePreview rewrites, the task converts
      legacy list, single, and selection datasources; expands listing filters,
      actions, selection actions, and supported exports into Spark blocks; and
      preserves Meta and JSON-LD path/mutator behavior.

      The task also updates `Brando.Villain.list_villains/0`, legacy listing
      `filter:` keys, root Docker digest commands, and font cache suffixes. It
      adds the Brando Repo configuration when exactly one Ecto Repo is
      available.

      Continue in this order:

        1. Review the complete Igniter diff, then run `mix format` and
           `mix compile --warnings-as-errors`.
        2. Run `mix brando.migrate55` for the 0.54 to 0.55 source changes. Its
           notice continues with the database migration workflow.

      See `guides/migrating_from_053.md` in Brando for the full recovery,
      rebaseline, and gettext instructions.
      """)
    end

    defp add_warnings(igniter) do
      Igniter.add_warning(igniter, """
      Manual 0.54 decisions remain:

        * Search for `Brando.Type.Video` and legacy embedded video values. Moving
          them to `Brando.Videos.Video` requires an application-specific schema
          and data migration; a module-name substitution would corrupt storage.
        * Review application templates for legacy ref paths such as
          `refs.name.data.data.path` and `gallery_images`. Brando migrations
          update database-stored module and fragment code, but cannot identify
          the semantics of every source-controlled template.
        * The task rewrites `use Brando.Datasource` only inside Blueprint
          modules. Search for any remaining uses in standalone Ecto schemas and
          move those datasource declarations onto the appropriate Blueprint.
        * Legacy listing `field`, `template`, and positional `child_listing`
          declarations require an application-specific row component or child
          schema. Exports using the removed `after_export` callback and action
          option sets beyond `default_actions:` also remain for manual redesign.
        * Vite 5 manifest configuration, custom Sharp-based processing, merged
          admin Create/Update LiveViews, `<.head>` adoption, and navigation markup
          depend on the application's frontend and custom code. Apply the
          corresponding 0.54 changelog instructions manually where relevant.
        * Back up Gettext catalogs before attempting recovery. After extracting
          the backend and frontend catalogs, run the copied helper explicitly
          with Bash, for example:

              bash scripts/sync_gettext.sh priv/gettext/backend/no/LC_MESSAGES

          Review its diff; it only fills empty single-line translations from
          sibling `.po` files and cannot decide plural or contextual translations.
      """)
    end
  end
else
  defmodule Mix.Tasks.Brando.Migrate54 do
    use Mix.Task

    @doc "Requests recompilation when optional Igniter support becomes available."
    def __mix_recompile__?, do: Code.ensure_loaded?(Igniter)

    @shortdoc "Migrates a Brando 0.53 application to 0.54 (requires igniter)"
    @moduledoc """
    #{@shortdoc}.

    This task is built on Igniter, an optional Brando dependency. Add it to your
    application's deps, run `mix deps.get`, then recompile Brando with
    `mix deps.compile brando --force` to enable the task.
    """

    @impl Mix.Task
    def run(_argv), do: Mix.Brando.missing_igniter!("brando.migrate54")
  end
end
