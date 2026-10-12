if Code.ensure_loaded?(Igniter) do
  defmodule Mix.Tasks.Brando.Migrate54 do
    @doc "Requests recompilation when optional Igniter support is removed."
    def __mix_recompile__?, do: not Code.ensure_loaded?(Igniter)

    use Igniter.Mix.Task

    alias Mix.Brando.Igniter.AdminFormViews
    alias Mix.Brando.Igniter.SourceUpgrade
    alias Mix.Brando.Igniter.SourceUpgrade.BlueprintGettext
    alias Mix.Brando.Igniter.SourceUpgrade.BuiltinActions
    alias Mix.Brando.Igniter.SourceUpgrade.ConfigRewrites
    alias Mix.Brando.Igniter.SourceUpgrade.ListingRows
    alias Mix.Brando.Igniter.SourceUpgrade.ViewHelpers

    @shortdoc "Migrates application source from Brando 0.53 to 0.54"
    @moduledoc """
    #{@shortdoc}.

    Run this task from a clean, committed worktree after updating the Brando
    dependency. It rewrites legacy Blueprint and LivePreview syntax, turns
    legacy listing `field`/`template` columns into a `listing_row/1` row
    component where it can convert every column, removes listing actions that
    repeat the built-in edit, duplicate and delete actions, writes Blueprint
    labels given as `gettext("...")` with `t/1`, preserves legacy Meta and
    JSON-LD path extraction semantics, creates the gettext recovery helper,
    and moves Gettext backends to `use Gettext.Backend`.

    The task changes source files only, and every rewrite matches 0.53 syntax
    only, so rerunning it is safe. An application that already uses 0.54
    syntax is left unchanged. Continue with `mix brando.migrate55` for the
    0.54 to 0.55 changes; the complete ordered workflow is documented in
    `guides/migrating_from_053.md`.
    """

    def info(_argv, _source) do
      %Igniter.Mix.Task.Info{group: :brando}
    end

    # Loads dependencies and configuration only; the application's source is
    # what this task fixes, so it may not compile yet.
    @impl Mix.Task
    def run(argv), do: Mix.Brando.Igniter.SourceTask.run(__MODULE__, argv)

    def igniter(igniter) do
      igniter
      |> SourceUpgrade.rename_list_villains()
      # These two read the Villain attributes the Blueprint rewrite removes.
      |> SourceUpgrade.upgrade_054_templates()
      |> SourceUpgrade.warn_block_editor_options()
      |> SourceUpgrade.rewrite_blueprints(&SourceUpgrade.upgrade_054_blueprint/1)
      |> ListingRows.rewrite()
      |> BuiltinActions.remove()
      |> BlueprintGettext.rewrite()
      |> SourceUpgrade.rewrite_preview_targets()
      |> SourceUpgrade.configure_repo_module()
      |> SourceUpgrade.remove_sharp_processor()
      |> SourceUpgrade.rewrite_dockerfiles()
      |> SourceUpgrade.rewrite_font_urls()
      |> SourceUpgrade.copy_gettext_script()
      |> SourceUpgrade.update_gettext_backends()
      |> AdminFormViews.consolidate()
      |> ViewHelpers.upgrade()
      |> ConfigRewrites.upgrade()
      |> add_notices()
      |> add_warnings()
    end

    defp add_notices(igniter) do
      Igniter.add_notice(igniter, """
      Brando 0.54 source migration prepared.

      In addition to the Blueprint and LivePreview rewrites, the task moves
      each Villain editor (`input :data, :blocks` in a fieldset) to a
      form-level `blocks :blocks`, which renders below the tabs; points
      `entry.html` in the schema's own templates at `entry.rendered_blocks`;
      converts legacy list, single, and selection datasources; expands
      listing filters, actions, selection actions, and supported exports into
      Spark blocks; and preserves Meta and JSON-LD path/mutator behavior.

      Legacy listing columns become a row component: image fields
      `<.cover>`, url fields `<.url>`, a Liquid template linking to the
      entry's update form `<.update_link>` (markup after the link in its
      `:outside` slot), with `{{ entry.x }}`, `{% if entry.x %}` and
      `{% for x in entry.xs %}` written as HEEx. Language columns are dropped. A
      listing with any other column is left as it is and listed below.
      Actions whose event is `edit_entry`, `duplicate_entry` or
      `delete_entry` are removed from listings that keep `default_actions`,
      which already offers them. Labels the admin translates in the schema's
      domain (tabs, alerts, `label:`, `placeholder:`, `instructions:`,
      listing labels, `translate`) given as `gettext("...")` become
      `t("...")`.

      Generated admin `<Name>CreateLive`/`<Name>UpdateLive` pairs become one
      `<Name>FormLive`, written beside the `UpdateLive` it replaces and routed
      with `:create` and `:update`; edited pairs are listed below.

      The task also updates `Brando.Villain.list_villains/0`, legacy listing
      `filter:` keys, root Docker digest commands, and font cache suffixes. It
      adds the Brando Repo configuration when exactly one Ecto Repo is
      available, and removes `processor_module: Brando.Images.Processor.Sharp`
      (Brando refuses to boot with it; Vix is the default). Phoenix.View-era
      `ErrorHelpers`, `view/0` and `view_helpers/0`, which phoenix_html 4 no
      longer compiles, are deleted when nothing uses them, and their
      `use Phoenix.HTML` replaced when something does. A Phoenix
      application gets `listeners: [Phoenix.CodeReloader]` in `project/0`,
      and `config/*.exs` get `import Config` for `use Mix.Config` and
      Logger's `:warning` for `:warn`.

      Continue in this order:

        1. Review the complete Igniter diff and run `mix format`. Neither
           task compiles the application, which usually compiles only after
           both have run.
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
        * Positional `child_listing` declarations require a child schema.
          Exports using the removed `after_export` callback and action option
          sets beyond `default_actions:` also remain for manual redesign.
        * Vite 5 manifest configuration, custom processing that relied on
          sharp-cli, `<.head>` adoption, and navigation markup the template
          warning does not list depend on the application's frontend and
          custom code. Apply the corresponding 0.54 changelog instructions
          manually where relevant.
        * Back up Gettext catalogs before attempting recovery. After
          `mix brando.migrate55`, `mix brando.gettext.reconcile` extracts and
          merges them, and fills empty single-line translations from sibling
          `.po` files as `scripts/sync_gettext.sh` does. Review its diff; it
          cannot decide plural or contextual translations.
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
