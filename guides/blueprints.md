## Blueprints

### Identifier

### Absolute URL

### Schema

Storage changes are managed through versioned snapshots and reviewed Ecto migrations. See
[Blueprint migrations](blueprint_migrations.md) for generation, rollback, rename, legacy upgrade, and recovery
instructions.

#### Attributes

#### Relations

#### Assets

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
retain the existing behavior. `Brando.Trait.Sequenced` selects its built-in
compiler automatically. To also avoid making the runtime trait alias a
module-body compile dependency, use the equivalent `trait :sequenced` shorthand.
Brando's own schemas use this form and the matching `trait :status` shorthand;
applications may adopt them incrementally. The existing
`trait Brando.Trait.Sequenced` and `trait Brando.Trait.Status` forms remain
supported. These are compile-time optimizations and require no database
migration.

### Translations

### Listings

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

#### Listing Query
#### Fields
##### Field types
##### Templates
#### Filters
#### Actions
#### Selection Actions
#### Child Listings

### Forms
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
