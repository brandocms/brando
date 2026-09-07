# Blueprints

A Blueprint is the compile-time contract for one Brando content type. It owns
the Ecto schema and changeset, storage migrations, identifiers and URLs,
relations and assets, admin listings and forms, traits, datasources, metadata,
and translations. Brando validates this contract while the schema compiles so
invalid or ignored configuration fails before it reaches a request or a
production migration.

Generate a new resource with `mix brando.gen.blueprint Catalog Product`, then keep its Blueprint,
generated Ecto migrations, and migration snapshots under version control. Read
[Blueprint migrations](blueprint_migrations.md) before changing persisted
fields, relations, indexes, table identity, or primary keys.

The public entry points remain the conventional APIs shown in this guide:
`use Brando.Blueprint`, `use Brando.Query`,
`use BrandoAdmin.LiveView.Listing`, and `use BrandoAdmin.LiveView.Form`.
Compiler/runtime boundaries behind those APIs are internal implementation
details and do not require application rewrites.

## Identifier

An identifier is the human-readable representation Brando uses in selectors,
entry relations, and persisted identifier records. HEEx is preferred; Liquex
templates remain supported:

```elixir
identifier ~H"{@entry.title} [{@entry.category.name}]"
# or: identifier "{{ entry.title }} [{{ entry.category.name }}]"
```

The template receives the entry as `@entry` in HEEx or `entry` in Liquex.
Association paths are extracted into `__identifier_preloads__/0`, so declare the
association normally and let Brando preload it. Disable identifier generation
with `identifier false`. Database-backed Blueprints persist identifiers by
default; use `persist_identifier false` when they should only be generated at
runtime. Embedded Blueprints must disable identifiers.

Invalid template syntax and unsupported values fail during compilation with the
Blueprint setting and parser location instead of failing during rendering.

## Absolute URL

Absolute URL templates drive admin preview links, SEO, sitemaps, and identifier
URLs. Prefer HEEx and the Blueprint route helpers:

```elixir
# Localized route for a translatable entry
absolute_url ~H|{route_i18n(@entry, :project_path, :detail, [@entry.slug])}|

# Non-localized route
absolute_url ~H|{route(:project_path, :detail, [@entry.slug])}|

# Static path
absolute_url ~H"/projects/{@entry.slug}"
```

Use `route_i18n/4` when the entry has a language and the route should be scoped;
use `route/3` otherwise. Liquex strings remain supported for legacy Blueprints.
As with identifiers, Brando extracts association paths into
`__absolute_url_preloads__/0`. Use `absolute_url false` for entries without a
public URL. Invalid templates fail during compilation.

## Schema

### Root configuration

Blueprint identity is declared with literal naming values when the schema calls
`use Brando.Blueprint`:

```elixir
use Brando.Blueprint,
  application: "MyApp",
  domain: "Projects",
  schema: "Project",
  singular: "project",
  plural: "projects",
  gettext_module: MyApp.Gettext,
  router_scope: :projects,
  extensions: [MyApp.BlueprintExtension]
```

`application`, `domain`, and `schema` are PascalCase module segments;
`singular` and `plural` are snake_case identifiers. `gettext_module`,
`router_scope`, and `extensions` are optional. Unknown or duplicate options,
missing required names, malformed values, and non-module extensions fail with a
contextual Blueprint error before Gettext, Spark, or Ecto setup begins.

The module registry derives conventional context, schema, and admin targets from
these names; Brando's resource generator relies on that target convention. The
actual module that calls `use Brando.Blueprint` remains the Ecto owner. Generated
block and entries join schemas therefore reference the actual owner rather than
mistaking the convention-derived generator target for the parent schema.

Schema-level storage settings are validated after compile-time expressions have
been evaluated:

```elixir
table "projects_projects"
data_layer :database       # or :embedded
primary_key :id            # or :uuid
factory %{status: :draft}
```

Table and naming values use snake_case database identifiers, factories are plain
maps, and the supported primary keys are the canonical integer `id` and UUID
representations used by Blueprint relations and migrations. Schemas that
intentionally have no generated primary key may set `@primary_key false`.

Every Blueprint schema exports the conventional `t/0` struct type for specs and
Dialyzer. Applications may still declare a more precise `@type t`; Blueprint
detects it and leaves it unchanged. This is generated compile-time metadata and
requires no code migration, Igniter upgrade, or database migration.

These validation checks require no database migration. Fix declarations reported
during compilation. If a correction changes an existing table name or primary
key, write and deploy the storage migration first, then follow the explicit
rebaseline workflow in [Blueprint migrations](blueprint_migrations.md); the
Blueprint generator deliberately does not automate those destructive changes.

Storage changes are managed through versioned snapshots and reviewed Ecto migrations. See
[Blueprint migrations](blueprint_migrations.md) for generation, rollback, rename, legacy upgrade, and recovery
instructions.

Blueprint DSL declarations are evaluated while their schema compiles. When a declaration
needs Brando application configuration, prefer the lightweight runtime configuration
boundary so the schema does not compile against the application supervisor:

```elixir
alias Brando.RuntimeConfig

attribute :language, :language, languages: RuntimeConfig.get(:admin_languages)
```

Existing `Brando.config/1` calls remain supported. Applications can make this optional,
compile-time-only replacement incrementally; it does not change the stored schema and
requires no database migration.

Generated `changeset/5` functions execute their runtime pipeline through
`Brando.Blueprint.ChangesetRunner`. Casting and validation implementation changes therefore
do not make every Blueprint schema compile-connected to the runtime asset, relation, block,
constraint, uniqueness, and trait modules. This boundary is automatic:
`Brando.Blueprint.run_changeset/1`, `maybe_sequence/3`, and
`maybe_validate_required/2` remain compatible, and applications need no code or database
migration.

Schemas used as deletable nested associations can opt in with
`@allow_mark_as_deleted true`. When their generated changeset receives
`marked_as_deleted: true`, persisted entries are marked with Ecto's `:delete` action and
unsaved entries are ignored. Deletion intent bypasses field and association validation:
values on an entry being removed cannot make its parent changeset invalid. The flag is
virtual and does not require a database column.

### Context query compilation

Contexts generated for Blueprint schemas keep using the public query API:

```elixir
use Brando.Query
```

It provides the existing `query`, `mutation`, `filters`, `matches`, query-helper, and
JSONB helper macros without making the context compile against the runtime query engine.
The compiler/runtime split is internal: existing contexts and runtime calls such as
`Brando.Query.handle_list_query/6` remain unchanged. This compile-time dependency
optimization requires no code migration, Igniter upgrade, or database migration.

### Attributes

Array attributes always declare their element type, for example
`attribute :tags, {:array, :string}`; a bare `:array` is rejected. Blueprint
`:uuid` fields use `Ecto.UUID`, while the legacy `:timestamp` field maps to
Ecto's `:naive_datetime` schema type. These mappings affect the runtime schema
type, while Blueprint migration snapshots retain their database-oriented type.

Persisted attributes may keep a stable Elixir field name while mapping to a
different physical database column with Ecto's `source:` option:

```elixir
attribute :title, :string, source: :headline
```

Forms, changesets, and queries use `:title`; generated migrations, indexes, and
constraints use `:headline`. Physical sources must be atoms and must remain
unique after PostgreSQL's 63-byte identifier normalization. Virtual and
timestamp attributes cannot declare a source. See
[Blueprint migrations](blueprint_migrations.md#physical-ecto-sources) before
adding or correcting a source on an existing table.

Built-in attributes validate their option names and option scopes before Ecto
schema generation. The storage-relevant options are `default:`, `null:`,
`precision:`, `scale:`, `source:`, and `rename_from:`; Blueprint also supports
its validation options (`required:`, `unique:`, and `constraints:`) and Ecto's
schema-only field options such as `autogenerate:`, `read_after_writes:`,
`load_in_query:`, `redact:`, `skip_default_validation:`, and `writable:`.
Migration-only options are removed before calling `Ecto.Schema.field/3`, while
schema-only options are excluded from migration snapshots. Use the root
`primary_key` declaration rather than `primary_key: true` on an attribute.

`null: false` is a database constraint; `required: true` is changeset
validation. They are intentionally independent so drafts and staged data can
retain the existing Blueprint validation behavior. Decimal precision and scale
are declared together:

```elixir
attribute :amount, :decimal, precision: 12, scale: 4, null: false
```

Enums require a non-empty set of unique values. Plain atom lists and
atom-to-string mappings use text storage; atom-to-integer mappings use integer
storage. Both supported array spellings compile to the same Ecto and migration
types:

```elixir
attribute :visibility, :enum,
  values: [public: "public", private: "private"],
  default: :private

attribute :priority, :enum,
  values: [low: 1, high: 2],
  default: :low

attribute :formats, {:array, :enum},
  values: [:jpg, :png],
  default: [:jpg]
```

Defaults remain application values in the Ecto struct. Migration snapshots
store the value dumped by the Ecto type, so the examples above use database
defaults `"private"`, `1`, and `["jpg"]`. Custom `Ecto.Type` and
`Ecto.ParameterizedType` attributes likewise generate their primitive database
type and dumped default instead of treating the Elixir module name as a
PostgreSQL type. Custom parameterized types retain their own type-specific
options.

### Relations

Blueprint uses the same persisted foreign-key name for Ecto schema generation,
changeset casting, required validation, unique constraints, database constraints,
and generated migrations. The default for a `belongs_to` relation is
`:<relation>_id`; override it explicitly when the database column uses another
name:

```elixir
relation :creator, :belongs_to,
  module: MyApp.Users.User,
  foreign_key: :owner_id,
  null: false,
  required: true,
  unique: [with: :site_id]
```

If the foreign-key field must be declared as an attribute (for example, to use
field options not supplied by `belongs_to`), disable Ecto's automatic field and
declare the exact persisted name once:

```elixir
attributes do
  attribute :owner_id, :id
end

relations do
  relation :creator, :belongs_to,
    module: MyApp.Users.User,
    foreign_key: :owner_id,
    define_field: false,
    required: true
end
```

Use `source:` when the logical foreign-key field should remain conventional but
the physical column differs, for example `relation :creator, :belongs_to,
module: MyApp.Users.User, source: :owner_ref`. Embedded one/many relations also
accept a physical JSONB source. Other relation types reject `source:` because
they do not define an owner-table field.

`required` is a boolean for every relation, while `define_field` is a
belongs-to-only boolean. Unique `with:` and `prevent_collision:` fields must
name columns persisted by the same
Blueprint. Scope fields must be distinct and cannot repeat the field or foreign
key being made unique; otherwise the generated Ecto constraint and database
index would contain duplicate columns. Virtual attributes cannot be unique.
Invalid declarations are reported while the Blueprint compiles.

Like attributes, `null: false` on a generated belongs-to field is a migration
constraint and `required: true` is changeset validation. With
`define_field: false`, put `source:`, `null:`, and any primary-key declaration on
the separately declared foreign-key attribute or root schema; declaring them on
the relation is rejected so one field cannot have two competing storage
contracts.

Relation options are validated against the relation type before Ecto schema
generation. The public `relation` declaration remains unchanged; the main
option scopes are:

| Concern | Relation types |
| --- | --- |
| `foreign_key:`, `references:` | belongs-to, has-one, has-many |
| `source:` | belongs-to, embeds-one, embeds-many |
| `through:` | has-one, has-many |
| `join_through:`, `join_keys:`, `join_where:`, `join_defaults:` | many-to-many |
| `preload_order:` | direct has-one, has-many, many-to-many |
| `load_in_query:` | embeds-one, embeds-many |
| `sort_param:`, `drop_param:` | embeds-many and cast has-many |
| `null:`, `constraint_name:`, `define_field:`, `primary_key:`, `type:` | belongs-to |

Has-one and has-many `through:` declarations retain `module:` as Blueprint
metadata but compile to Ecto through associations without passing that module
as a queryable. Through associations cannot use `cast: true`, because Ecto
cannot cast through an association. Configure ordering, filtering, defaults,
and replacement/deletion behavior on the underlying associations; Ecto ignores
those options on the through declaration itself. Has-one, has-many, and many-to-many
relations require `cast: true` when `required:` or cast-helper messages/options
must be applied. Embeds and `entries` relations are cast by their dedicated
Blueprint adapters and do not accept a redundant `cast:` option.

`unique:` has two intentionally different relation-specific meanings. On a
belongs-to relation it declares the runtime constraint and generated database
index documented below. On a many-to-many relation it is Ecto's boolean
association option for checking duplicate entries; it creates no owner-table
index or Blueprint migration snapshot change.

Many-to-many `join_defaults:` require a join schema module in `join_through:`;
Ecto cannot apply join defaults when `join_through:` is only a table name.

A generated belongs-to field may declare `primary_key: true`. This is useful for
an associative schema whose foreign keys form its key; pair it with
`primary_key false` at the Blueprint root when there should be no generated
`id`. Initial migration generation records and creates the relation key. Adding,
removing, or changing column-level primary-key membership after a snapshot
exists is deliberately refused: write and verify the primary-key migration,
then rebaseline as described in
[Changes that require a hand-written migration](blueprint_migrations.md#changes-that-require-a-hand-written-migration).

Misspelled options, invalid `on_replace:`/`on_delete:` values, malformed join
keys, and options that Ecto or Blueprint would ignore now fail at Blueprint
compile time. Fixing only one of those declarations, enabling many-to-many
`unique: true`, or adopting has-one `through:` requires no database migration.
If the correction changes belongs-to storage (`source:`, `null:`, `type:`,
`references:`, `foreign_key:`, `constraint_name:`, or `on_delete:`), generate
and review a Blueprint migration; delete-rule changes affect a foreign-key
constraint and must be checked in both directions. Igniter cannot choose a
production delete rule or infer whether deployed data satisfies a new
constraint. See
[Relation option corrections](blueprint_migrations.md#relation-option-corrections).

`unique: [prevent_collision: scope]` reevaluates the unique value when either
that value or one of its scope fields changes. An arity-one collision callback
receives the current changeset and must return the Ecto query used to search for
candidates. If the callback scopes uniqueness by persisted columns, list those
columns in `with:`. Brando applies them to the callback query, Ecto constraint,
and generated unique index. Persisted entries are excluded from their own
collision query, so an update cannot suffix a value merely because it already
belongs to that row. Callback-only declarations remain globally unique at the
database layer. If any composite scope value is `nil`, collision suffixing is
skipped to match PostgreSQL's default unique-index handling of `NULL` values.

For cast collection relations, `required: true` also applies when a form or API
sends `nil`, an empty string/list/map, or a list containing only blank ID
sentinels. `has_many`, `many_to_many`, and `entries` reject those values with the
standard required error and honor `required_message`; optional collections
continue to clear to an empty list. Many-to-many ID params may use string or
atom keys. Malformed IDs and IDs the configured lookup cannot resolve add a
cast error instead of raising or being silently discarded. This is changeset
validation only and does not require an Igniter upgrade or database migration.

Complete entry preloads from `Brando.Blueprint.preloads_for/2` include direct
`has_one` associations as well as the existing belongs-to and collection
relations. A cast `has_many` relation honors its declared `preload_order`;
schemas with the sequenced trait default to `[asc: :sequence]` only when the
relation does not declare an order. These query corrections keep the existing
API and require no Igniter upgrade or database migration.

These checks require no database migration by themselves. If correcting a
declaration changes an existing column, foreign key, or index, generate and
review a Blueprint migration as described in
[Blueprint migrations](blueprint_migrations.md). If the database already uses a
custom foreign-key column and only the runtime declaration was inconsistent, no
schema migration is needed.

### Assets

Blueprint image, file, video, and per-media gallery configs are normalized into
their typed config structs. Compilation validates the runtime-critical fields:
upload paths, positive size limits, MIME type lists, booleans, image sizes and
formats, video strategies/metadata, file content disposition, and completion
callbacks. Deferred zero-argument config functions are validated when their
result is materialized.

At the asset declaration level, the supported options are `cfg`, `required`,
and `constraints`. Galleries additionally accept Ecto's `required_message`,
`invalid_message`, and `force_update_on_change` cast options. Unknown options
are rejected during compilation so a typo cannot silently weaken validation.
When a form clears a required gallery, its `required_message` is used and the
changeset error retains `validation: :required`; optional galleries continue to
clear normally. Correct newly reported declaration typos after upgrading. No
Igniter upgrade or database migration is required.

#### Requiring one of several assets

`required: true` marks a single asset as mandatory. When an entry is valid with
*either* of two assets — a listing that needs an image or a video — neither can
be required on its own. Use the `one_of` constraint instead:

```elixir
assets do
  asset :listing_image, :image,
    constraints: [one_of: [:listing_image, :listing_video]],
    cfg: :default

  asset :listing_video, :video, cfg: :default
end
```

The error attaches to the asset carrying the constraint, so declare it on the
one whose input should show the message, and drop `required: true` from both —
otherwise the form marks a field as mandatory that a sibling can satisfy. An
asset counts as present whether it was set as an association or as its `_id`
column, so both the picker and upload paths satisfy it.

Use `exactly_one_of` when the fields are alternatives rather than a fallback —
a media item holding an image *or* a video, never both:

```elixir
asset :image, :image,
  constraints: [
    exactly_one_of: [:image, :video],
    exactly_one_of_message: "requires either an image or a video"
  ],
  cfg: :default
```

That is normally paired with a database check constraint. The constraint remains
the guarantee, and the validation covers writes that go through the changeset —
but a race between two requests, or a direct `Repo.insert`, still reaches the
database. An undeclared constraint raises `Ecto.ConstraintError` there instead of
returning an invalid changeset, so declare it too:

```elixir
asset :image, :image,
  constraints: [
    exactly_one_of: [:image, :video],
    check: [must_have_one_media_type: "requires either an image or a video"]
  ],
  cfg: :default
```

The name must match the database constraint exactly. `check:` also accepts a
bare atom or a list of them, which use `check_message` — or `"is invalid"` when
that is unset.

Message overrides are declared alongside the constraint they belong to, inside
the same `constraints:` list. All three — `one_of`, `exactly_one_of` and
`check` — work on attributes and relations as well as assets, and unknown or
malformed constraint keys are rejected at compile time for every entity kind.

All three media types share one completion callback contract:

```elixir
asset :document, :file,
  cfg: %{
    completed_callback: &__MODULE__.file_uploaded/2
  }

asset :clip, :video,
  cfg: %{
    completed_callback: {MyApp.MediaCallbacks, :video_ready, [notify: true]}
  }
```

Functions receive `(asset, current_user)`. MFA callbacks receive those two
runtime arguments first, followed by `extra_args`. File callbacks run after the
file is stored, image callbacks after processing (including SVG), and video
callbacks after a local/S3 upload is stored or a Mux/Bunny/Cloudflare video first becomes
ready. Asynchronous processing and provider webhooks can retry, so callback side
effects should be idempotent.

Mux, Bunny, and Cloudflare are valid persisted video types. Unknown video strategies
are rejected during Blueprint compilation so they
cannot render dead upload controls.

These config and callback corrections do not alter database storage. No Ecto
migration or Igniter upgrade script is required. Compile after upgrading and fix
any invalid config reported with its asset name and field.

Function-based `config_target` values use the same normalization and validation
boundary as declarations in `assets do`. A partial map is merged into the
matching typed config before use. Returning `:db`/`:config_target`, returning a
config struct for another media type, or targeting a field declared as another
asset type is rejected. Upload-manager intake catches these resolution errors,
uses the typed default config, and stores the resolved target as `"default"`.

### Form loading and callbacks

An existing entry is loaded with `%{matches: %{id: id}}` by default. Use a
static query map to add fixed options; Brando always injects the entry ID into
the map's `:matches`:

```elixir
forms do
  form do
    query %{preload: [:illustrators]}
  end
end
```

Use a callback when the query itself is dynamic. Callback queries replace the
default and must return the complete query map, including an ID match when one
is required:

```elixir
query &__MODULE__.form_query/1

def form_query(id), do: %{matches: %{id: id}, preload: [:illustrators]}
```

Form `query`, `after_save`, and `redirect_on_save` callbacks accept either the
documented function arity or `{module, function, extra_args}`. Runtime arguments
come first and configured arguments are appended.

Alerts accept translated strings and one-argument function components. Alert
components receive `form`, `schema`, `current_user`, `form_cid`, and `form_id`
assigns:

```elixir
alert :info, &__MODULE__.editor_notice/1
alert :warning, {MyAppWeb.FormAlerts, :quota_notice, [limit: 10]}
```

Form error summaries use a configured string `label` when present. Inputs with
`label: :hidden`, blank/nil labels, and other non-text labels fall back to a
humanized field name. Errors attached to generated foreign keys such as
`:cover_video_id` resolve through the visible `:cover_video` input, so storage
field names do not leak into the editor message.

These runtime contract corrections do not change storage. No Ecto migration or
Igniter upgrade script is required; compile after upgrading and correct any
static query whose `:matches` value is not a map.

## Traits

Use atom shorthands for Brando's built-in traits and module names for custom traits:

```elixir
trait :revisioned
trait :scheduled_publishing
trait :sequenced, append: true
trait :soft_delete, obfuscated_fields: [:uri]
trait :status
trait :timestamped
trait :translatable
trait :blocks
trait MyApp.Trait.Searchable
```

Every built-in trait has an atom shorthand: `:blocks`,
`:blocks_prevent_circular_references`, `:cast_polymorphic_embeds`, `:creator`,
`:ensure_uid`, `:focal`, `:meta`, `:module_versioned`, `:password`, `:permalink`,
`:protect_password`, `:protect_role`, `:revisioned`, `:scheduled_publishing`,
`:sequenced`, `:soft_delete`, `:status`, `:timestamped`, `:translatable`,
`:validate_var_keys`, and `:watch_language`. The legacy `:villain` shorthand also
resolves but remains deprecated; use `:blocks` for new declarations.
The nested `Brando.Trait.Blocks.PreventCircularReferences` trait uses
`:blocks_prevent_circular_references`.

Full module declarations remain supported. Both forms register the same runtime
module and preserve trait options, so calls such as
`Page.has_trait(Brando.Trait.Revisioned)` and `Page.__trait__(Brando.Trait.Sequenced)`
continue to use module names.

Blueprint invokes a trait's `generate_code/2` callback while compiling each
schema. Runtime-heavy custom traits can keep that compile path small by moving
the same callback to a focused compiler module:

```elixir
defmodule MyApp.Trait.Searchable.Compiler do
  def generate_code(_schema, _opts) do
    quote do
      attributes do
        attribute :search_text, :string
      end
    end
  end
end

defmodule MyApp.Trait.Searchable do
  use Brando.Trait

  alias MyApp.Trait.Searchable.Compiler

  @impl true
  def generate_code(schema, opts), do: Compiler.generate_code(schema, opts)

  # Runtime callbacks and helper functions stay in this module.
end
```

Opt into that compiler explicitly at each use site:

```elixir
trait MyApp.Trait.Searchable,
  compile_with: MyApp.Trait.Searchable.Compiler,
  ranking: :weighted
```

`compile_with:` is consumed by the Blueprint DSL and is not included in the
runtime trait options; all other options remain unchanged. Traits without it
retain the existing behavior. Brando's built-in traits with schema declarations select
focused compiler modules automatically: `Brando.Trait.Creator`, `Brando.Trait.Meta`,
`Brando.Trait.ScheduledPublishing`, `Brando.Trait.Sequenced`,
`Brando.Trait.SoftDelete`, `Brando.Trait.Status`, `Brando.Trait.Timestamped`, and
`Brando.Trait.Translatable`. To also avoid making the runtime trait alias a module-body
compile dependency, use their equivalent `trait :creator`, `trait :meta`,
`trait :scheduled_publishing`, `trait :sequenced`, `trait :soft_delete`,
`trait :status`, `trait :timestamped`, and `trait :translatable` shorthands. Brando's
own schemas use these forms; applications may adopt them incrementally. The existing
full module forms remain supported. These are compile-time optimizations and require no
database migration.

Runtime-only traits that inject no attributes, assets, or relations can use the reusable
no-op compiler while retaining their validation and changeset/save callbacks:

```elixir
trait MyApp.Trait.Validated,
  compile_with: Brando.Trait.NoopCompiler,
  runtime_option: :preserved
```

Brando's `EnsureUID`, `Permalink`, and `ValidateVarKeys` traits select this boundary automatically.
Use their `trait :ensure_uid`, `trait :permalink`, and `trait :validate_var_keys` shorthands to also avoid
a module-body dependency on the runtime trait. Existing full module declarations remain
supported and require no application or database migration.

### Permalink redirects

Add `trait :permalink` to a blueprint with an `absolute_url` definition to offer
redirects when editors change an existing entry's key, slug, or URL:

```elixir
trait :permalink
absolute_url ~H"/articles/{@entry.slug}"
```

After a successful admin save, Brando compares the previous and saved URLs and
shows the proposed permanent (301) redirect. The editor can create it or continue
without it; either choice completes the selected save action. New entries,
unchanged URLs, and entries with `has_url: false` do not prompt. Built-in pages
include this trait.

When the URL changes, any exact permalink redirect on the new URL is removed from
the saved entry's language before the prompt appears. This also happens when the
editor chooses **Continue without redirect**, closes the prompt, or renames back
to a previous URL. Pattern rules that may cover other pages are preserved.

Confirmed redirects are stored in the previous language's SEO settings and match
the exact old path, so changing `/about` does not redirect `/about/team`. The
language must already have SEO settings. Redirect creation failures leave the
saved entry intact and allow retrying or continuing without the redirect.

## Datasources

Datasource keys and nested metadata keys must be unique. A `:list` datasource
requires `list`; `:single` requires `get`; and `:selection` requires both. Brando
checks those contracts while the Blueprint compiles instead of failing later in
template rendering or the block editor.

Both callbacks accept an anonymous function or an MFA tuple. Runtime arguments
come first, followed by configured arguments:

```elixir
datasources do
  datasource :published do
    type :list
    list {MyApp.Projects, :list_for_datasource, [status: :published]}
  end
end

def list_for_datasource(module, language, vars, opts) do
  # ...
end
```

The equivalent runtime call is
`MyApp.Projects.list_for_datasource(module, language, vars, status: :published)`.

## Metadata and JSON-LD

A Blueprint has at most one `meta_schema` and one `json_ld_schema`; extraction
returns one metadata definition and one structured-data entity. Use repeated
`Brando.Plug.HTML.put_json_ld/3` calls when a page needs multiple JSON-LD entities.

Metadata targets must be non-empty strings. JSON-LD validation ensures that the
root is an available struct, every declared field exists on that struct, field
names are unique, value-producing types have callbacks, derived types do not
carry ignored callbacks, and nested schema modules export `build/1`. Optional
date and datetime callbacks may return `nil`, and extracting from a Blueprint
without a JSON-LD schema returns `nil`.

Metadata helpers `fallback/2` and `try_path/2` accept paths that cross mixed
maps, structs, keyword lists, and indexed lists, for example
`[:settings, :seo, :images, 0, "url"]`. A step that does not match its current
container returns `nil` instead of raising, allowing the next fallback path to
run. `false`, `0`, and `""` are values rather than missing data. This runtime
behavior uses the existing helper API and requires no migration.

## Translations

Translation context keys must be unique, as must translation keys inside each
context. Duplicate declarations fail compilation instead of being silently
overwritten when the DSL is converted to its runtime map.

## Listings

Listing validation covers non-negative limits, unique filter/sort/export/child
keys, valid sort orders, complete action events, CSV export contracts, select
options and defaults, and child-listing references. Static select filters need
at least one unique option value; dynamic selects use an arity-one callback.
Active filter defaults are merged into the initial query, while `nil`, `false`,
and empty defaults remain inactive and explicit values in `listing.query` take
precedence.

These datasource, metadata, JSON-LD, translation, and listing checks do not alter
database storage and require neither an Ecto migration nor an Igniter upgrade
script. Compile the application after upgrading and correct any rejected DSL
declarations. Review listing filter defaults because they now perform their
documented runtime function; removing an unintended default is an application
configuration change, not a database migration.

### Listing LiveViews

Generated admin listing LiveViews keep using the public setup API. Internally, setup
compilation is isolated so changes to runtime listing hooks do not recompile every
listing definition:

```elixir
use BrandoAdmin.LiveView.Listing, schema: MyApp.Projects.Project
```

Existing `use BrandoAdmin.LiveView.Listing, schema: ...` declarations, hook behavior,
listing APIs, and routes are unchanged. Dashboard LiveViews may use the same public API
with `schema: nil`. This compile-time dependency optimization requires no code
migration, Igniter upgrade, or database migration.

### Listing components

Blueprints with custom listing rows must explicitly import the lightweight core
components. Import cover images or child-listing actions only when the row uses
them. Blueprints without custom rows should not import listing components.

#### Example

```elixir
  import Brando.Blueprint.Listings.Components.Core

  listings do
    listing do
      query %{status: :published}
      filter label: t("Title"), key: "title"
      action label: t("Create subpage"), event: "create_subpage"
      action label: t("Create fragment"), event: "create_fragment"
      component &__MODULE__.listing_row/1
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.update_link entry={@entry} columns={10}>
      {@entry.title}
    </.update_link>
    <.url entry={@entry} />
    """
  end
```

Rows using `<.cover>` additionally import
`Brando.Blueprint.Listings.Components.Cover`; rows using `<.children_button>`
import `Brando.Blueprint.Listings.Components.Children`. Limit either import with
`only: [cover: 1]` or `only: [children_button: 1]`. The original
`Brando.Blueprint.Listings.Components` facade remains compatible when gradual
migration is preferable. Child-listing buttons target their owning listing row
automatically; existing `<.children_button entry={@entry} fields={...} />` calls
need no event target or migration changes.

### Listing query

`query` is the initial map passed to the normal Brando query pipeline. Use it for
preloads, ordering, status, and other fixed query options. Filter defaults fill
only missing filter keys; an explicit value in `query.filter` wins.

```elixir
listing do
  query %{preload: [:creator], order: [{:desc, :inserted_at}]}
  limit 50
  sortable true
end
```

### Filters and sorts

Filters require unique string keys and support `:text`, `:boolean`, and
`:select`. Select filters use either nested static `option` declarations or an
arity-one options callback receiving `%{language: language}`. Static values must
be unique. A non-empty `default` becomes part of the initial query only when the
query does not already provide that filter.

```elixir
filter label: t("Title"), key: "title"

filter do
  label t("Status")
  key "status"
  type :select
  option t("Published"), "published"
  option t("Draft"), "draft"
end

sort :newest, label: t("Newest"), order: [{:desc, :inserted_at}]
```

### Actions and exports

`action` adds a row-level action and `selection_action` adds an action for the
current selection. Each action needs a label and event; row actions may add a
boolean or string `confirm`. `default_actions false` removes Brando's built-in
row actions. CSV exports require a unique name, label, and list of fields and may
provide a dedicated query and description.

```elixir
action label: t("Duplicate"), event: "duplicate", confirm: true
selection_action label: t("Publish"), event: "publish_selected"

export :editorial do
  label t("Editorial export")
  fields [:title, :status, :inserted_at]
  query %{order: [{:asc, :title}]}
end
```

### Child listings

A child listing connects a named child-listing route to its schema. Names and
schema references must be unique and valid. Render the trigger with
`<.children_button>` from
`Brando.Blueprint.Listings.Components.Children`; the component targets its
owning row automatically.

```elixir
child_listing do
  name :chapters
  schema MyApp.Books.Chapter
end
```

## Forms

### Form LiveViews

Generated admin form LiveViews keep using the public setup API. Internally, setup
compilation is isolated so changes to runtime form hooks do not recompile every form
definition:

```elixir
use BrandoAdmin.LiveView.Form, schema: MyApp.Projects.Project
```

Existing `use BrandoAdmin.LiveView.Form, schema: ...` declarations, hook behavior,
routes, and form APIs are unchanged. The Brando generator emits this same public API.
No code migration, Igniter upgrade, or database migration is required.

### Form options

Forms are named; the default form uses `:default`, and additional forms use
`form :name`. `default_params` initializes new entries. `query`, `after_save`,
and `redirect_on_save` accept their documented function arity or an MFA tuple
whose configured arguments are appended after runtime arguments.

```elixir
form do
  default_params %{"status" => "draft"}
  query %{preload: [:creator]}
  after_save &__MODULE__.after_save/2
end
```

### Tabs, alerts, and fieldsets

A form contains tabs; each tab contains alerts and fieldsets. Fieldsets control
layout with `size`, `align`, `shaded`, and `style`. Alerts use `:info`,
`:warning`, or `:error` and accept a string or one-argument function component.

```elixir
tab t("Content") do
  alert :info, &__MODULE__.editor_notice/1

  fieldset do
    size :half
    align :start
    shaded false
    input :title, :text, label: t("Title")
  end
end
```

### Inputs

An `input` targets an attribute, asset, relation, or explicitly managed form
field and selects the admin renderer by type. Common renderers include `:text`,
`:textarea`, `:rich_text`, `:toggle`, `:status`, `:slug`, `:select`,
`:multi_select`, `:entries`, `:image`, `:video`, `:file`, `:gallery`, and
`:hidden`. Options are renderer-specific. The form verifier rejects inputs that
cannot be reconciled with their Blueprint field or relation rather than allowing
a broken form to reach runtime.

Use `blocks :blocks, ...` for a block editor field. Inputs may be hidden with a
boolean, `{field, expected_value}`, or one-argument form predicate. Constant
option lists should be assigned by the LiveView rather than rebuilt in HEEx.

Custom `inputs_for` renderers accept component modules as before. For Brando's
built-in renderers, prefer symbolic tokens so schema compilation stays independent
of the admin component tree:

```elixir
inputs_for :vars do
  component :vars
end
```

The available built-in tokens are `:vars`, `:gallery_objects`,
`:identity_type_config`, and `:page_vars`. Existing full module values remain
supported and can be migrated incrementally. This changes only form metadata and
requires no database migration.

#### AI input generation

Add `ai: [...]` to `:text`, `:textarea`, and `:rich_text` inputs to show an AI action button in the admin.
Clicking the button performs server-side generation and replaces the field value.
For `:rich_text` fields, prompt the model to return HTML (not Markdown), since the editor stores HTML.

```elixir
input :meta_description, :textarea,
  ai: [
    prompt: "Write a succinct meta description based on title and intro",
    context: [:title, :intro, :blocks]
  ]
```

If `model` is omitted in field options, Brando uses `Brando.AI` app config:

```elixir
config :brando, Brando.AI,
  enabled: true,
  default_model: "openai:gpt-4o-mini",
  providers: [
    openai: [api_key: System.get_env("OPENAI_API_KEY")]
  ],
  fields: [
    summary: [prompt: "Summarize title and intro", context: [:title, :intro]],
    teaser: [prompt: "Write a short teaser from title and intro", context: [:title, :intro]]
  ],
  default_opts: [temperature: 0.4]
```

`meta_title` and `meta_description` are rendered in the Meta drawer.
Meta trait defaults are trait-driven. You can configure those fields either:
1. directly on the trait in the blueprint, or
2. by defining regular form inputs with `ai: [...]` so drawer reuses blueprint opts.

```elixir
trait :meta,
  ai: [
    meta_title: [prompt: "Write SEO title from title", context: [:title]],
    meta_description: [prompt: "Write SEO description from title and blocks", context: [:title, :blocks]]
  ]
```

```elixir
input :meta_description, :textarea,
  hidden: true,
  ai: [
    prompt: "Write a succinct meta description based on title and rendered blocks",
    context: [:title, :blocks]
  ]
```

### Subforms and custom components

`inputs_for` renders a `:has_many`, `:embeds_many`, `:has_one`, or `:embeds_one`
relation as a nested form. Set `cardinality`, `style`, `size`, and an optional
default map, struct, or two-argument callback. Transformer styles turn selected
image/video assets into related entries and are compile-checked against the
related Blueprint's asset fields.

```elixir
inputs_for :items do
  cardinality :many
  style :inline
  default %{}

  input :title, :text
  input :enabled, :toggle
end
```

For a custom built-in renderer, set `component` to `:vars`,
`:gallery_objects`, `:identity_type_config`, or `:page_vars`. Existing component
modules remain supported. Transformer entries may supply a one-argument
`listing` function component.

### Subform presentation

Use `inputs_for` for nested relations. `style :regular` shows a complete form for
each entry; `style :inline` places the fields next to one another. For longer
collections, `style :listing` shows a compact summary with an **Edit** button:

```elixir
inputs_for :prices do
  cardinality :many
  style :listing
  listing &__MODULE__.price_summary/1
  default %MyApp.Prices.Price{}

  input :title, :text, label: "Title"
  input :price, :text, label: "Price"
end

def price_summary(assigns) do
  ~H"""
  <strong>{@entry.title || "New price"}</strong>
  <small>{@entry.price || "Set a price"}</small>
  """
end
```

The listing function receives `@entry` with pending changes applied. Keep the
summary short and meaningful: a title and the information that distinguishes
this entry from its neighbours. New entries open for editing, and validation
errors reveal their fields. Collapsing a row keeps its fields in the form, so
unsaved values still submit. **Done** collapses the editor; save the parent form
to persist changes. Listing style requires `cardinality :many`, a `listing`
function, and the built-in subform component. Set `add_entry false` to hide the
add button while retaining editing, ordering, and removal.

Transformers use their listing component as a summary too. Without one, they
show each entry's fields directly in a list, including when `layout :grid` was
requested. Supply a listing component to use compact rows or grid cards with
an explicit editor.
