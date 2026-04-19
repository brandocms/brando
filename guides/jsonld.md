## JSON-LD

Brando outputs structured data as [JSON-LD](https://json-ld.org/) using the
[schema.org](https://schema.org) vocabulary. All entities are combined into a
single `@graph` document, following the approach recommended by Google.

### How it works

Every page automatically gets a connected graph with:

- **Identity** (Organization, Corporation, ProfessionalService, LocalBusiness, or Restaurant)
- **WebSite** — linked to identity via `@id`
- **WebPage** — linked to website via `isPartOf`, type selectable per page
- **BreadcrumbList** — if breadcrumbs are set, linked from WebPage
- **Content entity** — Article, Event, CreativeWork, etc. from the blueprint DSL

The output is a single `<script type="application/ld+json">` tag:

```json
{
  "@context": "https://schema.org",
  "@graph": [
    {"@type": "Organization", "@id": "https://example.com/#identity", ...},
    {"@type": "WebSite", "@id": "https://example.com/#website", ...},
    {"@type": "WebPage", "@id": "https://example.com/about#webpage", ...},
    {"@type": "BreadcrumbList", "@id": "https://example.com/#breadcrumb", ...},
    {"@type": "Article", "@id": "https://example.com/about#article", ...}
  ]
}
```

### Blueprint DSL

Define structured data fields for your blueprint's content type:

```elixir
json_ld_schema JSONLD.Schema.Article do
  field :author, :identity
  field :copyrightHolder, :identity
  field :creator, :identity
  field :publisher, :identity

  field :copyrightYear, :integer, & &1.inserted_at.year
  field :dateModified, :datetime, & &1.updated_at
  field :datePublished, :datetime, & &1.inserted_at

  field :description, :string, &fallback([&1.meta_description, {:strip_tags, &1.intro}])
  field :headline, :string, & &1.title
  field :name, :string, & &1.title
  field :image, :image, & &1.meta_image
  field :inLanguage, :language
  field :keywords, :string, &__MODULE__.keywords(&1.case_categories)
  field :mainEntityOfPage, :current_url
  field :url, :current_url
end
```

#### Field types

| Type | Description |
|------|-------------|
| `:identity` | Creates `{"@id": "hostname/#identity"}` reference to site identity |
| `:datetime` | Converts to ISO 8601 string |
| `:date` | Converts to `YYYY-MM-DD` string |
| `:image` | Builds an `ImageObject` with url, width, height |
| `:current_url` | Uses the page's current absolute URL |
| `:language` | Extracts the language from the entry or meta |
| `:string` | Direct string value via `value_fn` |
| `:integer` | Direct integer value via `value_fn` |
| `{:list, SchemaModule}` | Maps over a list, calling `SchemaModule.build/1` on each item |
| `SchemaModule` | Calls `SchemaModule.build/1` on the extracted value |

#### List type example

Map over a collection of items to build nested schema objects:

```elixir
json_ld_schema JSONLD.Schema.Event do
  field :name, :string, & &1.title
  field :startDate, :datetime, & &1.start_date
  field :performer, {:list, JSONLD.Schema.Person}, & &1.performers
end
```

### Available schema modules

| Module | schema.org type | Use case |
|--------|-----------------|----------|
| `JSONLD.Schema.Article` | Article | Blog posts, news, pages |
| `JSONLD.Schema.CreativeWork` | CreativeWork | Generic creative content |
| `JSONLD.Schema.Event` | Event | Events with dates |
| `JSONLD.Schema.ExhibitionEvent` | ExhibitionEvent | Art exhibitions |
| `JSONLD.Schema.Person` | Person | Author/creator |
| `JSONLD.Schema.Place` | Place | Physical location |
| `JSONLD.Schema.ImageObject` | ImageObject | Image metadata |

Identity schemas (`Organization`, `Corporation`, `ProfessionalService`,
`LocalBusiness`, `Restaurant`) are handled automatically based on the
identity type configured in the admin.

### Controller usage

#### Adding a content entity

```elixir
{:ok, case} = Cases.get_case(%{matches: %{slug: slug}})

conn
|> assign(:case, case)
|> put_title(case.title)
|> put_meta(Cases.Case, case)
|> put_json_ld(Cases.Case, case)
|> put_section("case")
|> render(:detail)
```

#### Adding breadcrumbs

```elixir
{:ok, exhibition} = Exhibitions.get_exhibition(%{matches: %{slug: slug}})

breadcrumbs = [
  {gettext("Home"), "/"},
  {"Exhibitions", "/exhibitions"},
  {exhibition.title, "/exhibitions/#{exhibition.slug}"}
]

conn
|> put_json_ld(:breadcrumbs, breadcrumbs)
|> put_json_ld(Exhibitions.Exhibition, exhibition)
|> render(:detail)
```

Breadcrumb URLs are automatically converted to absolute URLs.

#### Multiple entities per page

You can call `put_json_ld/3` multiple times to add multiple entities to the
graph. Each call appends to the list:

```elixir
conn
|> put_json_ld(Events.Event, event)
|> put_json_ld(Events.Venue, venue)
```

#### Extra fields at runtime

Pass additional fields that aren't in the blueprint DSL:

```elixir
extra = [%{name: :image, type: :image, value_fn: &get_hero_image/1}]
put_json_ld(conn, MyApp.Blog.Post, post, extra)
```

### WebPage type

Pages have a `json_ld_type` attribute (default: `"WebPage"`) that controls the
`@type` of the auto-generated WebPage entity. Available types:

- `WebPage` (default)
- `Article`
- `AboutPage`
- `ContactPage`
- `CollectionPage`
- `ItemPage`
- `ProfilePage`

This is configurable per page in the admin under the Advanced tab.

When `json_ld_type` is set, it also overrides the `@type` on the content entity
extracted from the blueprint DSL. This means you can keep using
`json_ld_schema JSONLD.Schema.Article` in the blueprint (for the field
definitions) while the output type becomes whatever the editor selected.

### Identity type-specific fields

The Identity form includes type-specific fields that populate additional
schema.org properties based on the selected identity type:

| Type | Additional fields |
|------|-------------------|
| Organization | `foundingDate`, `numberOfEmployees` |
| Corporation | `foundingDate`, `numberOfEmployees`, `tickerSymbol` |
| ProfessionalService | `foundingDate`, `areaServed`, `knowsAbout` |
| LocalBusiness | `openingHours`, `priceRange`, `areaServed`, `geo` |
| Restaurant | `openingHours`, `priceRange`, `servesCuisine`, `hasMenu`, `geo` |

These are stored in the `type_config` embedded schema on Identity and
automatically included in the JSON-LD output.

### Custom schema modules

Create your own schema module for types not covered by the built-in ones:

```elixir
defmodule MyApp.JSONLD.Schema.Product do
  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@type": "Product",
            "@id": nil,
            name: nil,
            description: nil,
            image: nil,
            offers: nil

  def build(data) when is_map(data) do
    %__MODULE__{
      name: data.name,
      description: data.description
    }
  end
end
```

Then use it in your blueprint:

```elixir
json_ld_schema MyApp.JSONLD.Schema.Product do
  field :name, :string, & &1.title
  field :description, :string, & &1.description
  field :image, :image, & &1.cover
end
```
