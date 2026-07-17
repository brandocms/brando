## Blueprints

### Identifier

### Absolute URL

### Schema

#### Root configuration

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

#### Context query compilation

Contexts generated for Blueprint schemas keep using the public query API:

```elixir
use Brando.Query
```

It provides the existing `query`, `mutation`, `filters`, `matches`, query-helper, and
JSONB helper macros without making the context compile against the runtime query engine.
The compiler/runtime split is internal: existing contexts and runtime calls such as
`Brando.Query.handle_list_query/6` remain unchanged. This compile-time dependency
optimization requires no code migration, Igniter upgrade, or database migration.

#### Attributes

Array attributes always declare their element type, for example
`attribute :tags, {:array, :string}`; a bare `:array` is rejected. Blueprint
`:uuid` fields use `Ecto.UUID`, while the legacy `:timestamp` field maps to
Ecto's `:naive_datetime` schema type. These mappings affect the runtime schema
type, while Blueprint migration snapshots retain their database-oriented type.

#### Relations

Blueprint uses the same persisted foreign-key name for Ecto schema generation,
changeset casting, required validation, unique constraints, database constraints,
and generated migrations. The default for a `belongs_to` relation is
`:<relation>_id`; override it explicitly when the database column uses another
name:

```elixir
relation :creator, :belongs_to,
  module: MyApp.Users.User,
  foreign_key: :owner_id,
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

`required`, `define_field`, and `virtual` options are booleans. Unique `with:`
and `prevent_collision:` fields must name columns persisted by the same
Blueprint; virtual attributes cannot be unique. Invalid declarations are
reported while the Blueprint compiles.

For cast collection relations, `required: true` also applies when the form sends
an empty string to clear the collection. `has_many`, `many_to_many`, and
`entries` reject that value with the standard required error and honor
`required_message`; optional collections continue to clear to an empty list.
This is changeset validation only and does not require an Igniter upgrade or
database migration.

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

#### Assets

Blueprint image, file, video, and per-media gallery configs are normalized into
their typed config structs. Compilation validates the runtime-critical fields:
upload paths, positive size limits, MIME type lists, booleans, image sizes and
formats, video strategies/metadata, file content disposition, and completion
callbacks. Deferred zero-argument config functions are validated when their
result is materialized.

At the asset declaration level, the supported options are `cfg` and
`required`. Galleries additionally accept Ecto's `required_message`,
`invalid_message`, and `force_update_on_change` cast options. Unknown options
are rejected during compilation so a typo cannot silently weaken validation.
When a form clears a required gallery, its `required_message` is used and the
changeset error retains `validation: :required`; optional galleries continue to
clear normally. Correct newly reported declaration typos after upgrading. No
Igniter upgrade or database migration is required.

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
callbacks after a local upload is stored or a Mux/Bunny video first becomes
ready. Asynchronous processing and provider webhooks can retry, so callback side
effects should be idempotent.

Mux and Bunny are valid persisted video types. Cloudflare and S3 remain reserved
video strategies and currently return `:not_implemented` from the uploader.

These config and callback corrections do not alter database storage. No Ecto
migration or Igniter upgrade script is required. Compile after upgrading and fix
any invalid config reported with its asset name and field.

Function-based `config_target` values use the same normalization and validation
boundary as declarations in `assets do`. A partial map is merged into the
matching typed config before use. Returning `:db`/`:config_target`, returning a
config struct for another media type, or targeting a field declared as another
asset type is rejected. Upload-manager intake catches these resolution errors,
uses the typed default config, and stores the resolved target as `"default"`.

#### Forms

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

### Traits

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

Brando's `EnsureUID` and `ValidateVarKeys` traits select this boundary automatically.
Use their `trait :ensure_uid` and `trait :validate_var_keys` shorthands to also avoid
a module-body dependency on the runtime trait. Existing full module declarations remain
supported and require no application or database migration.

### Datasources

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

### Metadata and JSON-LD

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

### Translations

Translation context keys must be unique, as must translation keys inside each
context. Duplicate declarations fail compilation instead of being silently
overwritten when the DSL is converted to its runtime map.

### Listings

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

#### Listing LiveViews

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

#### Listing components

Blueprints with custom listing rows must explicitly import the lightweight core
components. Import cover images or child-listing actions only when the row uses
them. Blueprints without custom rows should not import listing components.

##### Example

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

#### Listing Query
#### Fields
##### Field types
##### Templates
#### Filters
#### Actions
#### Selection Actions
#### Child Listings

### Forms

#### Form LiveViews

Generated admin form LiveViews keep using the public setup API. Internally, setup
compilation is isolated so changes to runtime form hooks do not recompile every form
definition:

```elixir
use BrandoAdmin.LiveView.Form, schema: MyApp.Projects.Project
```

Existing `use BrandoAdmin.LiveView.Form, schema: ...` declarations, hook behavior,
routes, and form APIs are unchanged. The Brando generator emits this same public API.
No code migration, Igniter upgrade, or database migration is required.

#### Form options
#### Tabs
#### Fieldsets
#### Inputs

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

##### Input types
##### AI input generation

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
trait Brando.Trait.Meta,
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

##### Inputs for (subforms)
##### Inputs for (custom components)
