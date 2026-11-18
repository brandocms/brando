# Module definitions as files

Brando can export modules created in the admin to an Elixir DSL, then import
edits into the same database records. A definition includes its template, refs,
vars, editor settings, defaults, children and table template. You can also author
a new module entirely in files.

The guarantee is a **semantic round trip**: export → read → import without edits
does not duplicate modules, replace their identities, bump versions, synchronize
blocks or enqueue renders. Export produces canonical source; it does not recover
comments or formatting from previously authored files.
Empty values use the same schema normalization when exporting and reading, so
legacy blank values do not produce spurious updates or writes on reimport.

This workflow supports standalone applications and local modules in a selected
tenant environment. The admin's copy/install export is also available.

## Using the admin

Open **Block modules → Import / export → Modules as files**. Both directions use
the same definitions, authorization checks and importer as the CLI.

1. Choose **Prepare export**, then **Download ZIP** for all local modules in the
   current workspace. To export particular modules, select their listing rows and
   choose **Export DSL files**. Child modules and required table templates travel
   with the selected module trees.
2. Unzip the bundle, edit its `.exs`, `.heex` or `.liquid` files, and zip them
   together with `modules.lock.json`. Files may be at the archive root or inside
   one enclosing folder. Keep the baseline with your edits.
3. Upload the ZIP under **Import definitions** and choose **Preview import**.
   The preview lists creates, updates, unchanged definitions, conflicts and
   required migrations. Expand a definition to inspect current and imported
   values and the affected block/entry counts. Preview and cancellation do not
   write definitions.
4. Choose **Apply import** after reviewing the changes. Conflicts and required
   migrations disable this action. The server rechecks permissions and the
   baseline at apply time, including changes made after opening the preview.
5. Choose **Download updated ZIP** after a successful import. This preserves
   the uploaded source, comments and templates, and advances the baseline. Use
   this updated bundle for your next edit; the browser cannot update your original
   local ZIP in place. The result also reports refresh failures and offers
   **Retry refresh** without reimporting definitions.

For another installation or tenant environment, expand **Importing into another
site?** and enter a JSON object mapping external tokens to destination record
IDs (see [Media and content references](#media-and-content-references)). Missing
mappings are reported before a plan can be applied. The modal identifies the
current workspace; it does not switch the active site or environment.

ZIP uploads are limited to 5 MB compressed, 20 MB expanded and 500 entries.
Only definitions, templates and the baseline lockfile are accepted; archive
traversal and overlapping paths are rejected. macOS `.DS_Store` and `__MACOSX`
metadata are ignored. A disconnected/reloaded page requires a new upload and
preview. Temporary files are removed after reading; uploaded contents and the
preview are held only in the current LiveView session.

The **Import modules** and **Export modules** actions create copies using the
legacy encoded format. Use the DSL actions to update existing module
identities.

## Export, edit, inspect, import

Run the framework upgrade migrations first. Migration 172 adds and backfills
stable UIDs for table templates, in public and existing tenant schemas.

<!-- usage-rules:start topic="module-definitions" -->

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

An import re-renders the entries that use the changed modules, and the command
waits until they have rendered before it returns, printing its progress. With
no server running, its own Oban queue renders them; with one running, either
can. It exits non-zero, naming the entries, when a render fails or when
`--timeout SECONDS` (default 600) passes first. `--no-wait` leaves the renders
queued for the running server and says how many: the command then runs no
queue of its own, and without a server they wait until one starts. `refresh`
and `resolve --apply` take the same options.

<!-- usage-rules:end -->

Export requires a **new directory**. It writes:

- One `.exs` file per module or table template, named `<namespace>/<name>.exs`
  in the admin language (`default_admin_language`), and `tables/<name>.exs` for
  table templates. A child module goes in a folder beside its parent,
  `<namespace>/<parent>/<child>.exs`, whatever its own namespace. Definitions
  that would share a name get a short UID digest appended. The Elixir module
  name follows the path, e.g. `BrandoDefinitions.Sections.Hero`.
- One adjacent `.heex` or `.liquid` file per module, preserving its source bytes.
- `modules.lock.json`, containing the format version, source scope, definition
  digests and external reference bindings. No database credentials are included.

Names are only for people. Identity is the `uid` inside each file, so you can
rename files and move them between folders; keep each `template_file` path,
which is relative to its `.exs` file, pointing at the template.

Use repeatable `--uid UID` on export to select module trees. Selecting a child
includes its root, siblings, descendants and required table templates. This
prevents a partial export from accidentally detaching an existing child.

Commit the DSL, templates and lockfile together. After a successful import the
CLI updates the lockfile to the applied baseline, leaving authored source alone.
That baseline lets you make another edit and import again. A dry run changes
neither database definitions nor files.

### Importing on save in development

`Brando.Content.Definition.Watcher` runs the import whenever a definition or
template in the directory changes:

```elixir
# config/dev.exs
config :brando, Brando.Content.Definition.Watcher,
  path: "priv/modules",
  user_id: 1
```

Tenant applications also set `site:` and `environment:`. The directory must
exist (export it first), and `FileSystem` must be loaded, which Phoenix apps get
in dev through `phoenix_live_reload`. Each save plans the whole directory: a
clean plan is applied and the lockfile advances; conflicts and required
migrations are logged and nothing is written; an unchanged save does nothing.
It applies without a preview, so never configure it in production.

While it runs, the admin shows which modules have a file: a marker with the
path in the module listing, and a notice in the module editor. Both warn when
the module changed in the admin after the file was imported (the file's next
save would be refused), when both sides changed, or when the file has changes
that are not imported. Set `PLUG_EDITOR` (as for Phoenix's error pages, e.g.
`vscode://file/__FILE__:__LINE__`) to link the path to your editor.

## Applying a release's definitions

A site's release ships its `priv/modules`, the same files the watcher imports
in development. Production applies them from there, after someone has
reviewed what they change, without moving a database or retyping a template
into the admin.

<!-- usage-rules:start topic="module-definitions" -->

```elixir
# config/config.exs (a new installation has it in config/brando.exs)
config :brando, Brando.Content.Definitions, release_path: "priv/modules"
```

<!-- usage-rules:end -->

A relative path is in the application's `priv` as the release has it
(`Application.app_dir/2`). Without `release_path`, none of this runs. With
`tenancy_mode: :multi`, write `{site_key}` where the site's key goes
(`"priv/modules/{site_key}"`); a site without that directory has no release
definitions. Without it, every site's environments are planned against the
same directory. With `:single`, every environment of the site is.

### Each database's own baseline

The lockfile describes the database the files were last imported into, which
is the developer's. Each database instead records, in
`content_definition_applies`, every definition applied to it from files: by a
release, `mix brando.modules import`, the admin's ZIP import or the watcher.
A release's definitions are planned against the latest record:

| Action | When |
| --- | --- |
| `update` | The files changed, and the database still equals what was last applied here. |
| `create` | The module doesn't exist here. |
| `noop` | The database already equals the files, or only the admin changed it since the last apply: that change stays. |
| `conflict` | The files changed, and the module was also changed in the admin since the last apply. The plan names who changed it and when, and the release and account of the last apply. |
| `migration_required` | As for any import. |

A definition with no record whose database copy equals the files is recorded
as applied (an adoption), when the release is planned. One that differs is a
conflict, "never applied from files", and nothing applies it until the
operator names it with `--replace UID` (`replace: ["uid"]`): its database copy
is then replaced with the release's, and the record says so. `replace` never
overrides a conflict on a definition applied here. A definition deleted here
after it was applied is a conflict too, which `replace` creates again; one in
the trash stays a conflict until it is restored. A conflict on a definition
applied here is settled by keeping the version here (`Release.keep_here/2`,
recorded as `kept`: the release's file waits no longer, and stays out of date
until a developer exports the module and commits it) or by taking the
release's (`discard: ["uid"]`, recorded as `replaced`). The record of each
apply keeps the definition it replaced, and the one it wrote.

The admin's ZIP import and `mix brando.modules import` use the same records
when the bundle's lockfile was written for another database, or the bundle
has none: an update development already imported is an update here, not a
conflict. Without a record, the lockfile's baseline counts when the database
equals it.

### Who sees what waits

Superusers review and apply a release's definitions. With groups
authorization, so may a group granted **Release module definitions · Apply**
(`brando.module_definitions.apply`): what they write is the release's code,
or what an apply replaced, never their own, so it isn't a superuser's alone as
module code is. No preset grants it.

On a node that serves, a few seconds after boot, Brando plans the release's
definitions against every environment in the background. Nothing is applied
at boot. With blue/green deploys the old release keeps serving while the new
one boots, and someone reviews the changes first. The result is kept with the
release's and the database's digests.

Only the environment that changed is planned again: when a module or table
template is saved or deleted, definitions are applied or imported, or the
environment is created, copied over or restored from an archive. A burst of
changes, such as a ZIP import or several saves in a row, is planned once,
half a second after the last (five seconds at most). The node that made the
change plans and sends the result to the other nodes, which keep it without
planning (`Brando.CacheSync`); a node running another release plans for
itself.

When anything isn't a `noop`, the dashboard tells them how many module
changes the release has that aren't applied yet, with a link to **Block
modules → Release changes**. Block modules marks each module that differs:
changed in this release, changed here since the release's version was
applied, both, or never applied from the release.

### Review and apply in the admin

**Block modules → Release changes** lists the release's definitions that
differ from this environment's, one row per module tree (a module with its
children and the table templates it uses), and a summary: the release, the
changes by action and by kind (`ModuleDiff` class) and the entries they
re-render. Each row has four tabs:

- **Template**: the template's diff, highlighted, or the definition's when
  only its fields change.
- **Refs & vars**: what changes in the refs, vars and fields, and what that
  does to the blocks that use them.
- **Entries**: the entries that use the tree, with their type, language,
  status and links, searchable and sortable.
- **Preview**: an entry's page as it is and with the release's definitions,
  side by side in the browser, at mobile, tablet or desktop width. The
  blocks that differ are outlined in both (**Mark changes** turns that off),
  **Full screen** gives the pair the whole window, and **Share preview**
  copies a shared preview link of the proposed page.

**Verify** (per tree, or **Verify all**) is a dry run: every affected entry
is rendered with the release's definitions, in the background on the node
that serves the page, and nothing is written. Each entry renders with
changes, renders the same, or fails, with the error and the block. **HTML
diff** shows each block's rendered HTML both ways. A run can be cancelled,
and the next one keeps what it found for the entries it doesn't render.

The rows that are ready are checked; one **Apply N changes** covers them.
Some need something first:

- **Conflict** (changed here and in the release): a three-way view of the
  version last applied, the one edited here (who and when) and the
  release's. **Keep the version edited here** leaves the module out and
  records the release's file as applied; Block modules marks the file out of
  date until a developer exports the module (**Block modules → Export**, or
  `mix brando.modules export`) and commits it to `priv/modules`. **Use the
  release's version** replaces the edit, which the apply's record keeps.
- **Never applied** from files: **Replace with the release's version**.
- **Needs a migration**: shown, locked, with what blocks it.

The confirmation repeats what the apply covers, the entries it re-renders,
what it leaves out, and the entries that failed in Verify. After the apply, a
banner follows the renders until every entry has rendered, and names those
that failed. Activity records the apply with the release version.

**Keep** and **Revert** wait for the renders. Revert applies again the
definitions the apply replaced, through the same plan and apply, and
re-renders their entries; a module edited here after the apply is left as
it is and listed as a conflict, and a module the apply created stays. An
apply can be reverted, with no time limit, until someone keeps it or the
next release apply confirms it. Each environment has its own applies.

### Review and apply on the server

<!-- usage-rules:start topic="module-definitions" -->

In a release, without Mix, `rpc` runs on the running node:

```sh
# What waits in each environment: counts by action and kind of change,
# the entries affected, and conflicts with who and when
bin/my_app rpc 'Brando.Content.Definitions.Release.status()'

# Apply module trees by UID (children and table templates go with them),
# or :all; --replace's counterpart is replace:, and discard: takes the
# release's version over an edit made here
bin/my_app rpc 'Brando.Content.Definitions.Release.apply!(["acme-hero"], user: 1)'
bin/my_app rpc 'Brando.Content.Definitions.Release.apply!(:all, user: 1)'
```

Each apply is a batch that can be kept or reverted
(`Brando.Content.Definitions.Release.Batches.keep/2` and `revert/2`, as the
admin's banner does) until the next apply confirms it.

In development, against the development database:

```sh
mix brando.modules plan --release --user 1
mix brando.modules apply --release --uid acme-hero --user 1
mix brando.modules apply --release --all --replace acme-card --user 1
```

<!-- usage-rules:end -->

Tenant applications pass `site: "acme", environment: "production"` (or
`--site` and `--environment`); `status/1` without them reports every
environment, and `apply!/2` needs them. `user:` is an active account that may apply
release definitions (a superuser, or with groups a member granted
`brando.module_definitions.apply`). Its ID is the record's `applied_by`. Apply refuses,
writing nothing, while a selected definition is a conflict or needs a
migration; `:all` names them, so they can be left out or resolved. Media and
content tokens an earlier apply bound here are reused; map new ones with
`references:` (`--references FILE`), as for an import. After applying, `apply!/2` waits until every entry that uses a changed
module has rendered again, on whichever node runs the jobs, printing its
progress (`timeout:` in milliseconds, 10 minutes by default; `wait: false`, or
`--no-wait`, leaves the renders queued for the running server). `status/1` and
`apply!/2` raise when they fail, a render fails or the timeout passes, so
`rpc` exits with a non-zero status; changes waiting are not a failure.

A deploy can say what waits, one line per environment:

```sh
bin/my_app rpc 'Brando.Content.Definitions.Release.status(format: :line)'
# 3 module changes waiting in release 1.4.0: https://example.com/admin/config/content/modules
```

`Brando.Content.Definitions.Release.plan/1` and `apply/2` return the same data
without printing: the plan with each definition's action, state, diff,
`ModuleDiff` class and affected blocks and entries, the counts, and the last
apply and admin edit. The apply's record and its definition writes share a
transaction.

<!-- usage-rules:start topic="module-definitions" -->

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
      label %{"en" => "Theme", "no" => "Tema"}
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

<!-- usage-rules:end -->

A var's `label` is what editors see above the field. Give it per admin
language as a map, as for `name`; editors see their own language, then the
default language, then any. A plain string, as in `show_intro`, is read as the
default language. Export always writes the map. `instructions` work the same
way. A select's `options` take the
same: `{"Light", "light"}` is a label in the default language, and
`%{"label" => %{"en" => "Light", "no" => "Lys"}, "value" => "light"}` gives
both.

<!-- usage-rules:start topic="module-definitions" -->

With `hero.heex` beside it:

```heex
<section class={["hero", @theme]}>
  <.ref block={@block} ref={:heading} />
  <p :if={@show_intro}>Explore our work.</p>
</section>
```

Exactly one template is required. Use `template_file :liquid, "hero.liquid"`
for Liquid, or an inline literal such as
`template :liquid, "<h1>{{ title }}</h1>"`. Relative template paths must stay
inside the definition directory; symlinks are rejected. Liquid prints values
without escaping them: see
[Writing templates safely](block_editor.md#writing-templates-safely).

The file reader accepts one `defmodule` per `.exs` file, literal values, DSL
declarations and `use Brando.Content.Definition`. Maps, keyword lists, lists,
atoms, strings, numbers and raw string sigils are supported. Functions, module
attributes, loops, arbitrary `use` statements and expressions such as
`System.get_env/1` are rejected by the reader. It does not evaluate the files.
HEEx templates remain trusted server-side code, just like templates edited in
the admin: planning compiles them, and rendering executes their expressions.
Planning or applying modules takes a superuser (or `:system`). Only import
definitions and templates from trusted authors.

<!-- usage-rules:end -->

### Metadata and identity

`uid` identifies the module lineage, independently of the Elixir module name,
filename, translated display name or namespace. Keep it when updating an
existing module. `name`, `namespace` and `help_text` use locale maps or keyword
lists. Other declarations are `class`, `svg`, `color`, `write_with_ai`,
`multi`, `sequence`, `datasource`, `datasource_module`, `datasource_type` and
`datasource_query`. Datasource configuration uses the same values as the
admin. `write_with_ai true` offers Write with AI in the module's text blocks;
left out, it is off.

Export preserves module UIDs and definition-ref UIDs. Existing vars match by
`key`; their database IDs remain local. Versions are managed by import and are
not authored in the DSL. Changed modules advance once; unchanged modules retain
their version and timestamps. Versions are migration markers, not immutable
rendering snapshots.

A newly authored ref may omit its UID: it is derived deterministically from the
module UID and ref name. Export makes that UID explicit. Keep it on subsequent
edits. To install a separate copy, use the admin copy workflow or author
new module, ref and table-template identities throughout the copied tree.
Changing only the module UID while retaining another module's ref UIDs is rejected.

### Refs: settings and initial content

<!-- usage-rules:start topic="module-definitions" -->

`ref :name, :type` declares a normal content ref. Available types include
`:header`, `:text`, `:picture`, `:media`, `:video`, `:gallery`, `:file`, `:blocks`,
`:html`, `:markdown`, `:markdown_source`, `:svg`, `:map`, `:input` and `:comment`.

<!-- usage-rules:end -->

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

An HTML ref's template, parameters and default values are protected
fields, so they go in `default`
([HTML refs](block_editor.md#html-refs)):

```elixir
refs do
  ref :embed, :html do
    default %{
      "text" => ~s(<div data-checkin="{{ checkin_id }}"></div>),
      "params" => [%{"key" => "checkin_id", "label" => "Check-in ID", "type" => "id"}],
      "values" => %{}
    }
  end
end
```

`available_blocks` takes `"picture"`, `"video"`, `"gallery"`, `"svg"` and
`"file"`, each with its own `template_*`. A file in a media slot is an
ordinary file ref: `{% ref refs.visual %}` renders the download link. To show
some files another way (play a Lottie animation, embed a PDF), declare the
slot with `headless_ref` and decide in the template:

```liquid
{% headless_ref refs.visual %}
{% if refs.visual.data.type == "file" %}
  <canvas data-animation="{{ refs.visual.file | media_url }}"></canvas>
{% else %}
  {% ref refs.visual %}
{% endif %}
```

The declaration is what gives the ref its slot in the block editor: a
`{% ref %}` inside `{% if %}` alone gets none.

Unknown settings and unsupported ref types fail validation. Export includes default and nil values so a later schema
default cannot quietly change an existing definition.

<!-- usage-rules:start topic="module-definitions" -->

A ref appears in the block editor where the template renders it
(`<.ref block={@block} ref={:note} />`, `{% ref refs.note %}`); a ref the
template never places isn't editable. This holds for a `:comment` ref too:
it renders nothing on the site, but still has to be placed to be written in
the editor.

### Vars: values, controls and layout

The DSL supports the schema's var types: `:boolean`, `:string`, `:text`,
`:rich_text`, `:image`, `:video`, `:gallery`, `:datetime`, `:color`, `:select`,
`:file`, `:link` and `:date`. A file that says `:html` reads as `:rich_text`, and
is written as `:rich_text` on its next export. Values retain the same
representation as in the admin; for example, date/datetime values use strings,
and a `:rich_text` default is sanitized rich text. `default` writes
`value_boolean` for booleans, an asset token for media vars, and `value` for the
remaining types.

Use `label`, `placeholder`, `instructions` and `options` for controls.
`label` and `instructions` (the help text editors see under the field) take a
string or a per-language map, `%{"en" => "Keep it short", "no" => "Hold den kort"}`;
`placeholder` takes a string. Options
accept `{label, value}` pairs or maps with `label` and `value`. Layout declarations
are `width` (`:full`, `:half`, `:third`, `:fourth`, `:auto`, `:fill`), `new_row`
and `placement` (`:content`, `:config`, `:hidden`). Var order is declaration order.
HEEx's reserved assign names cannot be used as var keys.

A `:link` var can point at an entry of any status. A template that loads that
entry (`{% assign e = card.identifier | get_entry %}`) gets it on the site only
while it is published, and in live preview whatever its status; publishing,
unpublishing or deleting the entry renders the pages that link to it again,
its own included
([Liquid tags and context](block_editor.md#liquid-tags-and-context)). Its
status reads as text, so `{% if e.status == "draft" %}` marks one in live
preview that is not out yet.

<!-- usage-rules:end -->

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
`link_default_type: :identifier` opens an empty link's dialog on Content
instead of URL (`:url`, the default); a link the editor has set keeps its own
type, and the editor can still switch tabs.

<!-- usage-rules:start topic="module-definitions" -->

### Var layout

The block editor lays out a block's vars in rows of twelve units, in
declaration order. `width` is the share of a row a var takes: `:full` (12
units, the default), `:half` (6), `:third` (4) or `:fourth` (3); `:auto` is as
wide as its control and `:fill` takes what the row has left. A var joins the
row before it when it fits there, up to four vars a row, and starts a new row
otherwise. `new_row true` starts a new row even when the var would fit.

A var without `width` is full width, so it has a row of its own. Leave text and
rich-text vars that way: a one-line field beside a multi-line one is hard to
read. Give short controls such as selects, colours and booleans a width to put
them side by side:

```elixir
vars do
  var :heading, :string do
    label "Heading"
  end

  var :size, :select do
    label "Size"
    width :third
    options [{"Small", "small"}, {"Large", "large"}]
  end

  var :align, :select do
    label "Alignment"
    width :third
    options [{"Left", "left"}, {"Centre", "centre"}]
  end

  var :tone, :select do
    label "Tone"
    width :third
    options [{"Light", "light"}, {"Dark", "dark"}]
  end

  var :intro, :text do
    label "Introduction"
  end
end
```

The heading takes the first row, the three selects share the second, and the
introduction takes the third. Vars with `placement :config` are laid out the
same way in the block's configuration dialog. In the module editor, the Editor
layout panel shows these rows: drag vars between rows and set their widths
there.

<!-- usage-rules:end -->

<!-- usage-rules:start topic="module-definitions" -->

### When a definition is invalid

An import, a dry run, the development watcher, a ZIP import in the admin and the
release review all read the files the same way, and refuse a bundle with an
invalid definition. Each problem is one line: the file (relative to the
application, or within the ZIP), the var or ref, the field, what it takes and
what it got:

```text
priv/modules/sections/hero.exs: var "theme": width must be one of full, half, third, fourth, auto, fill (got "huge")
priv/modules/sections/hero.exs: var "theme": placeholder must be a string (got a map)
priv/modules/sections/hero.exs: ref "embed": params[0].key is required
```

A problem found when planning against the database, with no file to name,
names the definition instead: `module "hero-test": var "theme": …`.

<!-- usage-rules:end -->

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

Markdown-source refs use typed tokens for their source and pinned/review version:

```elixir
ref :document, :markdown_source do
  default source_id: "product-docs", policy: :pinned, version_id: "product-docs-v1"
end
```

Map both tokens to destination records with `--references`, just like asset
tokens. Export records their `markdown_source` and `markdown_version` kinds in
the lockfile. Import checks source-read and publication permissions, connection
availability, and that the mapped version belongs to the mapped source. Source
configuration, credentials and document contents are not included in the bundle.
Use a blank ref if editors should select the document themselves.

## Plans, conflicts and migrations

The plan lists each definition's action, changed fields, affected block count
and affected entry count:

| Action | Meaning |
| --- | --- |
| `create` | This UID does not exist in the target. |
| `noop` | The target already has this complete definition. |
| `update` | The baseline matches and the change can use existing synchronization. |
| `conflict` | The target changed since export, or an update has no baseline. |

The baseline is the lockfile's when it was written for the target's
database, and otherwise what was last applied to the target (see
[Each database's own baseline](#each-database-s-own-baseline)).
| `migration_required` | The proposed change needs an explicit content migration. |

Changes to template source, metadata, ref configuration/defaults, var settings,
options/layout and additive refs/vars can be applied. Existing block values
continue to follow Brando's protected-content rules. Planning parses Liquid or
compiles HEEx, but does not render every affected entry or prove that all
datasource/runtime expressions will succeed.

The importer blocks removed/retyped refs and vars, ref identity changes,
moving existing children, removing child definitions, changing table columns,
and changes to the module contract (engine, multi, datasource or table binding).
There is no force switch that silently deletes editor content. Removing a
top-level definition file does not delete its database module. Use an explicit
migration for structural changes, then export a fresh baseline.

For a conflict, export the target into a new directory, review the admin changes
against your edits, and apply your intended changes onto that fresh export.
Do not discard or fabricate baseline digests to hide concurrent edits.

The baseline records a digest of each definition as it was exported. Empty
values (`nil`, `false`, `""`, `[]`, `%{}`) are left out of it, so a Brando
upgrade that adds a field to a block type or a var doesn't make untouched
definitions look changed. A lockfile without `"version": 2` in `baseline` is
compared exactly; the next import or export rewrites it.

Apply locks the definition tables and recalculates the plan before writing.
Changes after planning invalidate the plan. A database error rolls back all
definition writes in that import. Authorization and reference availability are
checked again at apply time.

After commit, imports use the existing module synchronization, cache eviction,
render enqueueing and module notifications. The result reports refresh as
`requested`, including any remaining stale block IDs. If refresh raises an
error, definitions remain committed. Retry it explicitly without changing their
versions:

```sh
mix brando.modules refresh --uid acme-hero --user 1
```

The CLI then follows the jobs that import or refresh queued, and no others:
the render of each affected entry, the renders those queue (the entries that
embed a fragment that was rendered) and any cascade. It prints how many entries
are done as they finish:

```
Applied 1 definition changes; baseline saved
Refresh requested for acme-hero; 0 stale blocks remain
Rendering entries: 0 of 12 done
Rendering entries: 7 of 12 done
Rendering entries: 12 of 12 done
Rendered 12 entries
```

A render that fails an attempt counts as failed at once: the command names the
entry and its error and exits non-zero, and Oban retries the render later on a
node that runs its queue. A render whose block template fails is not retried:
its job is cancelled with the failing blocks and their errors as its error, and
the entry keeps the HTML it had ([Villain parser](villain_parser.md#when-a-block-template-fails)). When the timeout passes, the command names the
entries still waiting and exits non-zero; their renders stay queued. Either
way, it stops the application before it returns, so a render its own queue
has started finishes.

While it waits, the command runs only Oban's `default` queue, where entry
renders run, and may take other jobs of that queue too; stopping, it gives a
job it is running 35 seconds, as long as a render may take. It never starts
the definition watcher. Use `--no-wait` in a deploy script that runs beside a server, when the
server should do the rendering.

If saving the new lockfile fails after commit, export into a new directory before
the next edit. The CLI reports this separately from an import rollback.

## Blocks left on an older version

A module save migrates every block that uses it, but never deletes what the
editor typed: a ref or var the new version no longer defines (a renamed or
removed one) stays in the block, and so does a ref whose type changed. Such a
block keeps its old `module_version` and stays stale, which `mix brando.doctor`
counts. A refresh re-renders it; it cannot bring it up to date.

The Legacy Content Wrapper, the module the 0.51 upgrade puts free-standing
blocks in (class `legacy-content`), is the exception for one ref: its `content`
ref holds a ref of any type, so a wrapped picture, video, HTML or comment is
never a leftover. Anything else its blocks hold that the wrapper does not
define is.

Resolve the leftovers in the admin, from the module's screen (Block modules →
the module → **Resolve blocks**, or the system check's link), or with the
`resolve` command. Each leftover is dropped or mapped onto a ref or var the
module defines now, in every block at once, with exceptions per block in the
admin. A var keeps its value when it moves to the same type, from string to
text, from single-line text to string, or from string or text to rich text; a select
value must be one of the target's options. A ref moves to a ref of a compatible
type. Anything else is refused, with the reason.

```sh
# what the blocks hold (a dry run)
mix brando.modules resolve --uid kulturslider --user 1
# drop `link`, move the old `title` ref onto `heading`
mix brando.modules resolve --uid kulturslider --user 1 --drop link --map title=heading
mix brando.modules resolve --uid kulturslider --user 1 --drop link --map title=heading --apply
```

Write `ref:KEY` or `var:KEY` when a ref and a var share a key. Resolving stores
a revision of every entry it changes first (History can restore it), re-syncs
the blocks with the module, stamps their version, renders them and their
entries, records the change in Activity, and moves editors who have an entry
open onto the new rows. It needs the right to update the module and every
entry. Entries in the trash count as entries: they are listed, marked as in
the trash, and get their revisions, so restoring one brings its content back
through History. An entry whose schema keeps no revisions, such as a
template, gets none; the review names it. A resolve is refused when anything
the blocks hold changed after the review, even where the shortened value it
shows did not. `Brando.Content.StaleBlocks` is the API both use.

## Calling the API

```elixir
alias Brando.Content.Definitions

{:ok, exported} = Definitions.export("priv/modules", user, uids: ["acme-hero"])
{:ok, bundle} = Definitions.read(exported.directory)
{:ok, plan} = Definitions.plan(bundle, user)

if Brando.Content.Definition.Plan.applicable?(plan) do
  {{:ok, result}, run} = Definitions.track_refresh(fn -> Definitions.apply(plan, user) end)
  {:ok, :ok} = Definitions.write_baseline(exported.directory, result)
  result.refresh

  %{rendered: rendered, failed: failed, pending: pending, timed_out: timed_out} =
    Definitions.await_refresh(run, timeout: :timer.minutes(10))
end
```

`track_refresh/1` runs an apply or a refresh (`Definitions.refresh/2`) and
returns its result with a run id that names the render and cascade jobs it
queued. `await_refresh/2` follows those jobs on whichever node runs them, by
polling the jobs table, until each entry has rendered or failed or the timeout
passes. `failed` and `pending` hold the schema, entry ID, tenant prefix, job
state and last error of each; a render whose block template failed is
`"cancelled"`, its error naming each block, its module and the template's error. `refresh_status/1` returns the same without
waiting. Call them right after the apply: they know the jobs by their rows,
which Oban's Pruner deletes a few minutes after they finish. The node that calls them needs no Oban queues of its own, but some
node must run the `default` queue for the renders to finish.

For compiled Spark definitions, call
`Definitions.from_modules([MySite.Definitions.Hero], root: "priv/modules")`.
Pass every referenced child and table-template module in that list. Compiled
modules are trusted application code; the literal-only restriction belongs to
`read/1`. Both paths produce the same canonical bundle.

API callers select a tenant with `Brando.Tenant.with_prefix/2` using a resolved
server-side site/environment. The actor's authorization scope must match that
target. Trusted maintenance callers may explicitly pass `:system`; planning
then also requires `creator: user_id` for newly inserted var/table records.

The importer does not publish to the shared library or manage its overrides,
pull or apply through Florist, run destructive migrations automatically, or
install or activate frontend assets. It does not change shared-source
provenance.
