# Module definitions as files

Brando can export modules created in the admin to an Elixir DSL, then import
edits into the same database records. A definition includes its template, refs,
vars, editor settings, defaults, children and table template. You can also author
a new module entirely in files.

The guarantee is a **semantic round trip**: export → read → import without edits
does not duplicate modules, replace their identities, bump versions, synchronize
blocks or enqueue renders. Export produces canonical source; it does not recover
comments or formatting from previously authored files.

This workflow supports standalone applications and local modules in a selected
tenant environment. The admin's existing copy/install export remains available.

## Export, edit, inspect, import

Run the framework upgrade migrations first. Migration 171 adds and backfills
stable UIDs for table templates, in public and existing tenant schemas.

From your Brando application's directory:

```sh
mix brando.modules export --out priv/modules --user 1
# Edit the .exs definitions and .heex / .liquid templates.
mix brando.modules import --from priv/modules --user 1 --dry-run
mix brando.modules import --from priv/modules --user 1
```

`--user` is an active account ID. Commands use that account's normal permissions;
being able to run Mix does not implicitly select a system actor. An export needs
export access to the selected modules and table templates. Imports need create or
update access to each definition, and read access to referenced media/content.

Tenant applications must supply both selectors on every command:

```sh
mix brando.modules export --out priv/modules \
  --user 1 --site acme --environment staging
mix brando.modules import --from priv/modules --dry-run \
  --user 1 --site acme --environment staging
```

There is no implicit live-environment default. The command restores the previous
tenant context on success or failure.

Export requires a **new directory**. It writes:

- One `.exs` file per module or table template, with deterministic names based on UID.
- One adjacent `.heex` or `.liquid` file per module, preserving its source bytes.
- `modules.lock.json`, containing the format version, source scope, definition
  digests and external reference bindings. No database credentials are included.

Use repeatable `--uid UID` on export to select module trees. Selecting a child
includes its root, siblings, descendants and required table templates. This
prevents a partial export from accidentally detaching an existing child.

Commit the DSL, templates and lockfile together. After a successful import the
CLI updates the lockfile to the applied baseline, leaving authored source alone.
That baseline lets you make another edit and import again. A dry run changes
neither database definitions nor files.

## Authoring a definition

```elixir
defmodule MySite.Definitions.Hero do
  use Brando.Content.Definition

  uid "acme-hero"
  name en: "Hero", no: "Topp"
  namespace en: "Sections"
  help_text en: "An introductory section"
  class "hero"

  refs do
    ref :heading, :header do
      description "Headline"
      config level: 1, placeholder: "Write a headline"
      default text: "Welcome"
    end
  end

  vars do
    var :theme, :select do
      label "Theme"
      default "light"
      options [{"Light", "light"}, {"Dark", "dark"}]
      placement :config
      width :half
      new_row true
    end

    var :show_intro, :boolean do
      label "Show introduction"
      default true
    end
  end

  template_file :heex, "hero.heex"
end
```

With `hero.heex` beside it:

```heex
<section class={["hero", @theme]}>
  <.ref ref={:heading} />
  <p :if={@show_intro}>Explore our work.</p>
</section>
```

Exactly one template is required. Use `template_file :liquid, "hero.liquid"`
for Liquid, or an inline literal such as
`template :liquid, "<h1>{{ title }}</h1>"`. Relative template paths must stay
inside the definition directory; symlinks are rejected.

The file reader accepts one `defmodule` per `.exs` file, literal values, DSL
declarations and `use Brando.Content.Definition`. Maps, keyword lists, lists,
atoms, strings, numbers and raw string sigils are supported. Functions, module
attributes, loops, arbitrary `use` statements and expressions such as
`System.get_env/1` are rejected by the reader. It does not evaluate the files.
HEEx templates remain trusted server-side code, just like templates edited in
the admin: planning compiles them, and rendering executes their expressions.
Only import definitions and templates from trusted authors.

### Metadata and identity

`uid` identifies the module lineage, independently of the Elixir module name,
filename, translated display name or namespace. Keep it when updating an
existing module. `name`, `namespace` and `help_text` use locale maps or keyword
lists. Other declarations are `class`, `svg`, `color`, `multi`, `sequence`,
`datasource`, `datasource_module`, `datasource_type` and `datasource_query`.
Datasource configuration uses the same values as the admin.

Export preserves module UIDs and definition-ref UIDs. Existing vars match by
`key`; their database IDs remain local. Versions are managed by import and are
not authored in the DSL. Changed modules advance once; unchanged modules retain
their version and timestamps. Versions are migration markers, not immutable
rendering snapshots.

A newly authored ref may omit its UID: it is derived deterministically from the
module UID and ref name. Export makes that UID explicit. Keep it on subsequent
edits. To install a separate copy, use the existing admin copy workflow or author
new module, ref and table-template identities throughout the copied tree.
Changing only the module UID while retaining another module's ref UIDs is rejected.

### Refs: settings and initial content

`ref :name, :type` declares a normal content ref. Available types include
`:header`, `:text`, `:picture`, `:media`, `:video`, `:gallery`, `:file`, `:blocks`,
`:html`, `:markdown`, `:svg`, `:map`, `:input` and `:comment`.

`config` and `default` are maps of the ref type's persisted data fields. They
must not declare the same field twice. Together they describe the complete
initial ref data. Export places fields protected by the block type, such as a
header's `text`, in `default`, and other fields in `config`. Those labels do not
override Brando's synchronization rules: each block type still decides which
editor values survive a definition update.

Refs also support `uid`, `description`, `active`, `collapsed` and `assets`.
Declaration order determines ref order. A blocks ref can declare
`config module_set: "all"`; the owned block subtree remains entry content and is
not exported with its definition.

Nested media templates use the same field names as the embedded schemas:

```elixir
refs do
  ref :visual, :media do
    config %{
      available_blocks: ["picture", "gallery"],
      template_picture: %{placeholder: "dominant_color", formats: ["webp"]},
      template_gallery: %{display: "grid", allowed_types: ["image"]}
    }
  end
end
```

Unknown settings and unsupported ref types fail validation rather than being
silently dropped. Export includes default and nil values so a later schema
default cannot quietly change an existing definition.

### Vars: values, controls and layout

The DSL supports the schema's var types: `:boolean`, `:string`, `:text`, `:html`,
`:image`, `:video`, `:gallery`, `:datetime`, `:color`, `:select`, `:file`, `:link`
and `:date`. Values retain the same representation as in the admin; for example,
date/datetime values use strings. `default` writes `value_boolean` for booleans,
an asset token for media vars, and `value` for the remaining types.

Use `label`, `placeholder`, `instructions` and `options` for controls. Options
accept `{label, value}` pairs or maps with `label` and `value`. Layout declarations
are `width` (`:full`, `:half`, `:third`, `:fourth`, `:auto`, `:fill`), `new_row`
and `placement` (`:content`, `:config`, `:hidden`). Var order is declaration order.
HEEx's reserved assign names cannot be used as var keys.

Additional persisted var settings belong in `settings`, for example:

```elixir
var :website, :link do
  label "Website"
  default "https://example.com"
  settings link_text: "Visit", link_type: :url,
    link_target_blank: true, link_allow_custom_text: false
end
```

This also covers color picker/opacity flags, media config targets, gallery
allowed types and link identifier schema restrictions. Export emits all of them.

## Children and table templates

Define dependencies in separate `.exs` files within the same directory tree.
Reference their UID, or their Elixir module name. For example, a multi module
can include:

```elixir
multi true

children do
  child MySite.Definitions.Card
  child "acme-quote"
end
```

Every child must exist in the bundle, may have only one parent, and cannot form
a cycle. Child declaration order controls child order. All definitions in the
bundle are planned and persisted in dependency order in one transaction.

A table template uses the same var declarations for columns:

```elixir
defmodule MySite.Definitions.Prices do
  use Brando.Content.Definition
  kind :table_template
  uid "acme-prices"
  name "Prices"

  vars do
    var :description, :string do
      label "Description"
    end
    var :price, :string do
      label "Price"
      width :third
    end
  end
end
```

The consuming module declares `table_template MySite.Definitions.Prices`.
Table templates match by UID, so two different templates may share a display
name. Table row values belong to entries and are never definition data.

## Media and content references

Media files and referenced records are not bundled or uploaded. A definition's
`assets` uses typed tokens instead of local foreign keys:

```elixir
ref :cover, :picture do
  assets image: "cover-photo"
end

var :logo, :image do
  label "Logo"
  default "brand-logo"
end
```

Export records the source bindings in the lockfile. Reimport into the same
installation and environment can reuse them. For a different destination, or
newly authored tokens, provide a JSON mapping:

```json
{"cover-photo": 42, "brand-logo": 81}
```

```sh
mix brando.modules import --from priv/modules --user 1 \
  --references destination-references.json --dry-run
```

Use the same mapping on the real import. All referenced records must exist in
the selected destination and be readable by the actor. Equal numeric IDs in
two environments are never assumed to refer to the same asset. Ref assets
support image, file, video and gallery; var assets additionally support palette
and identifier. Gallery-object override IDs are exported as typed tokens too.
Keep token names stable while editing. To replace an asset in the same destination,
use a new token with a new mapping; rebinding an existing token is rejected so its
baseline meaning cannot change.

## Plans, conflicts and migrations

The plan lists each definition's action, changed fields, affected block count
and affected entry count:

| Action | Meaning |
| --- | --- |
| `create` | This UID does not exist in the target. |
| `noop` | The target already has this complete definition. |
| `update` | The baseline matches and the change can use existing synchronization. |
| `conflict` | The target changed since export, or an update has no baseline. |
| `migration_required` | The proposed change needs an explicit content migration. |

Changes to template source, metadata, ref configuration/defaults, var settings,
options/layout and additive refs/vars can be applied. Existing block values
continue to follow Brando's protected-content rules. Planning parses Liquid or
compiles HEEx, but does not render every affected entry or prove that all
datasource/runtime expressions will succeed.

This first importer blocks removed/retyped refs and vars, ref identity changes,
moving existing children, removing child definitions, changing table columns,
and changes to the module contract (engine, multi, datasource or table binding).
There is no force switch that silently deletes editor content. Removing a
top-level definition file does not delete its database module. Use an explicit
migration for structural changes, then export a fresh baseline.

For a conflict, export the target into a new directory, review the admin changes
against your edits, and apply your intended changes onto that fresh export.
Do not discard or fabricate baseline digests to hide concurrent edits.

Apply locks the definition tables and recalculates the plan before writing.
Changes after planning invalidate the plan. A database error rolls back all
definition writes in that import. Authorization and reference availability are
checked again at apply time.

After commit, imports use the existing module synchronization, cache eviction,
render enqueueing and module notifications. The result reports refresh as
`requested`, including any remaining stale block IDs; it does not claim queued
renders have completed. If refresh raises an error, definitions remain committed.
Retry it explicitly without changing their versions:

```sh
mix brando.modules refresh --uid acme-hero --user 1
```

If saving the new lockfile fails after commit, export into a new directory before
the next edit. The CLI reports this separately from an import rollback.

## Calling the API

```elixir
alias Brando.Content.Definitions

{:ok, exported} = Definitions.export("priv/modules", user, uids: ["acme-hero"])
{:ok, bundle} = Definitions.read(exported.directory)
{:ok, plan} = Definitions.plan(bundle, user)

if Brando.Content.Definition.Plan.applicable?(plan) do
  {:ok, result} = Definitions.apply(plan, user)
  {:ok, :ok} = Definitions.write_baseline(exported.directory, result)
  result.refresh
end
```

For compiled Spark definitions, call
`Definitions.from_modules([MySite.Definitions.Hero], root: "priv/modules")`.
Pass every referenced child and table-template module in that list. Compiled
modules are trusted application code; the literal-only restriction belongs to
`read/1`. Both paths produce the same canonical bundle.

API callers select a tenant with `Brando.Tenant.with_prefix/2` using a resolved
server-side site/environment. The actor's authorization scope must match that
target. Trusted maintenance callers may explicitly pass `:system`; planning
then also requires `creator: user_id` for newly inserted var/table records.

Shared-library publication and overrides, remote Florist pull/apply, admin import
review screens, automatic destructive migrations and coordinated frontend asset
activation are follow-up work. This importer does not change shared-source
provenance or install frontend assets.
