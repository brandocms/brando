# Brando CMS - Commands and Style Guide

## Build & Test Commands
- Install dependencies: `mix deps.get`
- Compile project: `mix compile`
- Run Elixir tests: `mix test`
- Run specific test: `mix test path/to/test_file.exs:line_number`
- Run end to end tests: `cd e2e/e2e_project && ./test_e2e.sh`
- Code analysis:
  - Refactoring opportunities: `mix credo suggest --format json --all --only refactor`
  - Design: `mix credo suggest --format json --all --only design`
  - Readability: `mix credo suggest --format json --all --only readability`
  - Warnings: `mix credo suggest --format json --all --only warning`
  - Check single check example: `mix credo --format json --all --checks Credo.Check.Refactor.LongQuoteBlocks`
- Type checking: `mix dialyzer`
- Format code: `mix format`
- Reset database: `mix ecto.reset`
- Watch tests: `mix test.watch`

## Core Principles
- Write clean, concise, functional code using small, focused functions.
- **Explicit Over Implicit**: Prefer clarity over magic.
- **Single Responsibility**: Each module and function should do one thing well.
- **Easy to Change**: Design for maintainability and future change.
- **YAGNI**: Don't build features until they're needed.
- If any of my requests are not clear, ask me to clarify.
- If you have better suggestions, feel free to suggest them.

## Blueprints

Blueprints are Brando's core abstraction for defining content schemas with auto-generated admin interfaces, APIs, and database migrations. They provide a declarative DSL for building complete content management systems.

### Blueprint Structure
A blueprint should be organized in this order:
1. **Attributes** - Schema fields and data types
2. **Assets** - File and image upload configurations  
3. **Relations** - Associations between schemas
4. **Listings** - Admin list view definitions
5. **Forms** - Admin form interface definitions
6. **Meta/JSON-LD** - SEO and structured data schemas
7. **Translations** - Internationalization setup
8. **Datasources** - Dynamic content queries (optional)

### Core Components

#### Attributes
Define schema fields with types and constraints:
```elixir
attributes do
  attribute :title, :string, required: true
  attribute :slug, :slug, required: true, unique: [prevent_collision: true]
  attribute :status, :enum, options: [draft: 0, published: 1, disabled: 2], default: :draft
  attribute :publish_at, :utc_datetime
  attribute :body, :text
  attribute :meta_data, :map
end
```

#### Assets  
Configure file and image uploads with module attributes:
```elixir
@image_cfg [
  allowed_mimetypes: ["image/jpeg", "image/png"],
  default_size: "medium",
  upload_path: Path.join(["images", "covers"]),
  random_filename: true,
  size_limit: 10_240_000,
  sizes: %{
    "thumb" => %{"size" => "150x150", "quality" => 65, "crop" => true},
    "medium" => %{"size" => "500x500", "quality" => 65, "crop" => true},
    "large" => %{"size" => "700x700", "quality" => 65, "crop" => true}
  },
  srcset: %{
    default: [
      {"medium", "500w"},
      {"large", "700w"}
    ]
  }
]

@file_cfg %{
  allowed_mimetypes: ["application/pdf"],
  upload_path: Path.join("files", "documents"),
  random_filename: false,
  size_limit: 10_240_000
}

assets do
  asset :cover, :image, cfg: @image_cfg
  asset :pdf_file, :file, cfg: @file_cfg
end
```

#### Relations
Define associations between schemas:
```elixir
relations do
  relation :category, :belongs_to, module: Category
  relation :tags, :many_to_many, module: Tag, join_through: "articles_tags"
  relation :comments, :has_many, module: Comment, preload_order: [desc: :inserted_at]
  relation :author, :belongs_to, module: User, cast: true
  relation :blocks, :has_many, module: :blocks
end
```

#### Listings
Configure admin list views:
```elixir
listings do
  listing do
    query %{
      order: [{:desc, :inserted_at}], 
      preload: [:category, :author]
    }
    
    sort :default, label: t("Default"), order: [{:desc, :inserted_at}]
    sort :title_asc, label: t("Title ↓"), order: "asc title"
    sort :title_desc, label: t("Title ↑"), order: "desc title"
    
    filter label: t("Title"), filter: "title"
    filter label: t("Status"), filter: "status"
    
    action label: t("Create entry"), event: "create_entry"
    action label: t("Duplicate"), event: "duplicate_entry"
    
    component &__MODULE__.listing_row/1
  end
end
```

#### Forms
Define admin form interfaces with blocks support:
```elixir
forms do
  form do
    default_params %{status: :draft}
    blocks :blocks, label: t("Content blocks")
    
    tab t("Content") do
      fieldset do
        input :status, :status, label: t("Status")
      end
      
      fieldset do
        size :half
        input :title, :text, label: t("Title")
        input :slug, :slug, label: t("Slug")
      end
      
      fieldset do
        input :cover, :image, label: t("Cover image")
        input :body, :textarea, label: t("Description")
      end
    end
    
    tab t("Meta") do
      fieldset do
        input :meta_title, :text, label: t("Meta title")
        input :meta_description, :textarea, label: t("Meta description")
      end
    end
  end
end
```

#### Meta Schema
SEO and social media metadata:
```elixir
meta_schema do
  field ["title", "og:title"], &fallback([Map.get(&1, :meta_title), Map.get(&1, :title)])
  field ["description", "og:description"], & &1.meta_description
  field "og:image", &Map.get(&1, :meta_image)
  field "og:locale", &encode_locale(try_path(&1, [:__meta__, :language]))
end
```

#### JSON-LD Schema  
Structured data for search engines:
```elixir
json_ld_schema JSONLD.Schema.Article do
  field :author, :identity
  field :copyrightHolder, :identity
  field :dateModified, :datetime, & &1.updated_at
  field :datePublished, :datetime, & &1.inserted_at
  field :description, :string, & &1.meta_description
  field :headline, :string, & &1.title
  field :inLanguage, :language
  field :name, :string, & &1.title
  field :url, :current_url
end
```

#### Translations
Internationalization configuration:
```elixir
translations do
  context :naming do
    translate :singular, t("article")
    translate :plural, t("articles")
  end
end
```

### Common Traits
Blueprints can include reusable traits:
- `Brando.Trait.Creator` - Adds creator tracking
- `Brando.Trait.Timestamped` - Adds inserted_at/updated_at
- `Brando.Trait.Status` - Adds status field with published/draft/disabled
- `Brando.Trait.Blocks` - Adds Villain block editor support
- `Brando.Trait.Meta` - Adds meta fields for SEO
- `Brando.Trait.SoftDelete` - Enables soft deletion
- `Brando.Trait.Sequenced` - Adds sequence/ordering
- `Brando.Trait.Translatable` - Adds multi-language support

### Blueprint Declaration
```elixir
defmodule MyApp.Projects.Project do
  use Brando.Blueprint,
    application: "MyApp",
    domain: "Projects", 
    schema: "Project",
    singular: "project",
    plural: "projects",
    gettext_module: MyAppWeb.Gettext

  trait Brando.Trait.Creator
  trait Brando.Trait.Timestamped
  trait Brando.Trait.Status
  trait Brando.Trait.Blocks
  
  # ... attributes, assets, relations, etc.
end
```

## Code Style Guidelines
- Follow Elixir style conventions
- Line length: 122 characters max (see .formatter.exs)
- Use descriptive variable and function names: e.g., `user_signed_in?`, `calculate_total`.
- Prefer higher-order functions and recursion over imperative loops.
- Use snake_case for variables and functions
- Module names in PascalCase
- Prefer pattern matching over conditionals
- Prefer using aliases over imports.
- Modules should have @moduledoc
- Public functions should have @doc
- Use explicit returns with :ok/:error tuples
- Import only what's needed with `import Ecto.Query, only: [from: 2]`
- Arrange Blueprint files with attributes, assets, relations, listings, forms
- Follow DSL conventions defined in .formatter.exs
- Follow standard Elixir practices and let `mix format <filename>` take care of formatting (run before committing code).

## Documentation and Quality
- Describe why, not what it does.
- **Document Public Functions**: Add `@doc` to all public functions.
- **Examples in Docs**: Include examples in documentation (as doctests when possible).
- **Cautious Refactoring**: Propose bug fixes or optimizations without changing behavior or unrelated code.
- **Comments**: Write comments only when information cannot be included in docs.