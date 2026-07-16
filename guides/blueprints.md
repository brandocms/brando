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

### Translations

### Listings

#### Example

```elixir
  listings do
    listing do
      query %{status: :published}
      filter label: t("Title"), filter: "title"
      action label: t("Create subpage"), event: "create_subpage"
      action label: t("Create fragment"), event: "create_fragment"
      component &__MODULE__.listing_row/1
    end
  end
```

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
