## JSON-LD

Brando outputs structured data as [JSON-LD](https://json-ld.org/) using the
[schema.org](https://schema.org) vocabulary. All entities are combined into a
single `@graph` document, following the approach recommended by Google.

### How it works

Every page automatically gets a connected graph with:

- **Identity** (Person, Organization, Corporation, ProfessionalService, LocalBusiness, Restaurant, …)
- **WebSite** — linked to identity via `@id`
- **WebPage** — linked to website via `isPartOf`, type selectable per page
- **BreadcrumbList** — if breadcrumbs are set, linked from WebPage
- **Content entity** — Article, Event, CreativeWork, etc. from the blueprint DSL
- **Person** — for each author the blueprint maps (see [Authors](#authors))
- **VideoObject** — for each video the entry shows (see [Videos](#videos))

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
  field :dateModified, :datetime, &Brando.Blueprint.Value.modified_at/1
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

#### dateModified

Search and answer engines show `dateModified` as "Updated …", and compare it
with the sitemap's `lastmod`. Read it with `Brando.Blueprint.Value.modified_at/1`
rather than `updated_at`, which moves on every save, block re-render and
`mix brando.entries.resave`.

`modified_at/1` returns `content_modified_at` for entries with `trait :meta`.
That column is set when an entry is created and moves only when a save changes
its text substantially: at least 10% of its words, and never fewer than 5 or
more than 20 words are needed. A typo fix, a reordering of blocks, a new meta
description or a resave leaves it alone. Entries without it fall back to
`edited_at`, then `updated_at`.

The text compared is the entry's `:text`, `:textarea` and `:rich_text` form
inputs (not slugs or the meta fields) and its rendered block fields. Tune the
threshold with:

```elixir
config :brando, Brando.Trait.Meta, substantive_change: [min_words: 5, max_words: 20, ratio: 0.1]
```

Use the same value for a visible "Updated" line in templates, so readers,
JSON-LD and the [sitemap](sitemaps.md) agree:

```heex
<p>Updated {Brando.Utils.Datetime.format_datetime(Brando.Blueprint.Value.modified_at(@post), "%d.%m.%Y")}</p>
```

#### Field types

| Type | Description |
|------|-------------|
| `:identity` | Creates `{"@id": "hostname/#identity"}` reference to site identity |
| `:person` | A Brando user, a People entry, a name, or a list of them, as linked `Person` nodes (see [Authors](#authors)) |
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

### Authors

Map who wrote an entry with the `:person` field type. Nothing is emitted for
an author unless the blueprint maps one, so admin users never appear in
structured data by accident:

```elixir
json_ld_schema JSONLD.Schema.Article do
  # a Brando user: `trait :creator` gives every entry one
  field :author, :person, & &1.creator
end
```

or People entries, from a relation:

```elixir
field :author, :person, & &1.authors
```

The callback may return one value or a list, and anything not preloaded is
skipped (it never queries). Each author becomes its own `Person` node in the
`@graph`, and the field holds a reference to it:

```json
{"@type": "Article", "author": {"@id": "https://example.com/people/ada/#person"}, ...},
{"@type": "Person", "@id": "https://example.com/people/ada/#person", "name": "Ada Lovelace", ...}
```

**Brando users** give their public profile only: `name`, `jobTitle` and
`sameAs` from the *Public profile* fields on the user form (Job title,
Profile links), and `image` from the avatar when it is preloaded
(`preload: [creator: %{module: Brando.Users.User, preload: [:avatar]}]`).
Never the email, role or anything else. A user has no public page, so the
`@id` is `https://example.com/#/schema/person/<hash>`, a hash of the user id
that stays the same across pages.

**People entries** use the People blueprint's own `json_ld_schema` when it is
a `Person`, so the author on an article and the person on their own page are
one node with one `@id`, `<the entry's absolute URL>/#person`:

```elixir
# MyApp.People.Person
json_ld_schema JSONLD.Schema.Person do
  field :name, :string, & &1.name
  field :jobTitle, :string, & &1.job_title
  field :sameAs, :string, & &1.profile_links
  field :image, :image, & &1.portrait
  field :url, :current_url
end
```

A People blueprint without a `Person` mapping is read by convention: `name`
(or the identifier's title), `job_title`, `same_as`, and the first preloaded
image of `avatar`, `portrait`, `image` or `photo`. Only those fields are
read, so a person's email or other columns stay out.

#### ProfilePage

When `put_json_ld/4` is given an entry whose schema is a `Person` — a People
entry on its own page — the page becomes a `ProfilePage` with that Person as
its `mainEntity`:

```json
{"@type": "ProfilePage", "@id": "https://example.com/people/ada/#webpage",
 "mainEntity": {"@id": "https://example.com/people/ada/#person"}, ...},
{"@type": "Person", "@id": "https://example.com/people/ada/#person", ...}
```

Google's [profile page](https://developers.google.com/search/docs/appearance/structured-data/profile-page)
result needs `mainEntity` with the person's `name`; `image`, `sameAs`,
`jobTitle` and `url` are recommended. Other `ProfilePage`s and `AboutPage`s
are about the site's identity, as before.

### Videos

Every entry whose schema has a `video` property (`Article`, `CreativeWork`)
describes the videos it shows as `VideoObject` nodes, linked from `video`, with
no blueprint changes. The videos are:

- the blueprint's video fields (`asset :cover_video, :video`), and
- the videos in its block fields: each active ref with a video, in active
  blocks and their children. A video block's title override names the video.

Only what is preloaded is read, so preload the video (and its `thumbnail`)
or the blocks where you want them described:

```elixir
preload: [cover_video: %{module: Brando.Videos.Video, preload: [:thumbnail]}]
```

A video shown twice is described once. The node's `@id` is site-wide,
`https://example.com/#/schema/video/<id>`.

Google needs three properties for a
[video result](https://developers.google.com/search/docs/appearance/structured-data/video),
and a video missing any of them gets no node:

| Property | Required | Taken from |
|----------|----------|------------|
| `name` | Yes | The video's title, or the video block's title |
| `thumbnailUrl` | Yes | The video's thumbnail image, else the provider's poster frame (Mux, Bunny, Cloudflare Stream, Vimeo) |
| `uploadDate` | Yes | When the video was added to Brando |
| `description` | Recommended | The video's caption |
| `duration` | Recommended | The duration the provider reported, as ISO 8601 (`PT2M10S`) |
| `contentUrl` | Recommended | The file or stream: Mux, Bunny, Cloudflare and Vimeo HLS, uploads, external files |
| `embedUrl` | Recommended | The player: Bunny, Vimeo and YouTube |

Signed Mux and Cloudflare videos have no public poster frame, so they are
described only when they have a thumbnail image. Videos that are not ready
are skipped.

To leave a blueprint's videos out, say so in its schema:

```elixir
json_ld_schema JSONLD.Schema.Article do
  videos false
  field :headline, :string, & &1.title
end
```

A blueprint that maps `video` itself keeps its own mapping. A custom schema
module gets automatic videos by having a `video` field.

### Available schema modules

| Module | schema.org type | Use case |
|--------|-----------------|----------|
| `JSONLD.Schema.Article` | Article | Blog posts, news, pages |
| `JSONLD.Schema.CreativeWork` | CreativeWork | Generic creative content |
| `JSONLD.Schema.Event` | Event | Events with dates |
| `JSONLD.Schema.ExhibitionEvent` | ExhibitionEvent | Art exhibitions |
| `JSONLD.Schema.Person` | Person | Author/creator (use the `:person` field type) |
| `JSONLD.Schema.VideoObject` | VideoObject | Built automatically from video fields and blocks |
| `JSONLD.Schema.Place` | Place | Physical location |
| `JSONLD.Schema.ImageObject` | ImageObject | Image metadata |
| `JSONLD.Schema.VisualArtwork` | VisualArtwork | An artwork, in a project's `hasPart` |

The identity schema is handled automatically from the identity type chosen in
the admin: Person, Organization, Corporation, ProfessionalService,
LocalBusiness, Restaurant, Architect, ArtGallery, EducationalOrganization,
EmploymentAgency, GovernmentOrganization, MedicalOrganization, NGO or
SportsOrganization.

### Controller usage

#### Adding a content entity

```elixir
# `case` is a reserved word in Elixir, so it can't name the variable
{:ok, project} = Cases.get_case(%{matches: %{slug: slug}})

conn
|> assign(:case, project)
|> put_title(project.title)
|> put_meta(Cases.Case, project)
|> put_json_ld(Cases.Case, project)
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

#### List pages (CollectionPage)

For controller actions that list multiple items (no single content entity),
use `put_json_ld_type/2` to set the WebPage type directly:

```elixir
def list(conn, _params) do
  {:ok, exhibitions} = Exhibitions.list_exhibitions(%{status: :published})

  conn
  |> put_json_ld_type("CollectionPage")
  |> put_breadcrumbs([{gettext("Home"), "/"}, {gettext("Exhibitions"), "/exhibitions"}])
  |> put_title(gettext("Exhibitions"))
  |> assign(:exhibitions, exhibitions)
  |> render(:list)
end
```

This sets `@type` on the auto-generated WebPage entity to `"CollectionPage"`
without requiring a content entity.

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

### Collections rendered by datasource blocks

`put_json_ld/4` assembles the graph from controller assigns, but a datasource
block resolves its entries during block rendering and the output is cached in
`rendered_<field>`. On a cached page the datasource never re-runs, so nothing
controller-side can see those entries.

Emit the node from the template instead, using the list the block just
rendered:

```liquid
{{ entries | json_ld: "CreativeWork" }}
```

```heex
<.json_ld entries={@entries} type="CreativeWork" />
```

Both go through `Brando.JSONLD.Collection.from_entries/2`, which builds an
`ItemList` (or a `CollectionPage` with the `page` flag) from every entry whose
Blueprint resolves an `absolute_url`, and renders it as an inline
`<script type="application/ld+json">`. Inline JSON-LD is valid anywhere in the
document; consumers merge it with the `@graph` in `<head>` by `@id`.

Because the markup is produced by the same render as the HTML, it is refreshed
when the entry is re-rendered and never fresher or staler than the listing it
describes. See the [datasources guide](datasources.md#describe-the-collection-for-crawlers).

### WebPage type

Pages have a `json_ld_type` attribute (default: `"WebPage"`) that controls the
`@type` of the auto-generated WebPage entity. Only valid
[schema.org WebPage subtypes](https://schema.org/WebPage) are available:

- `WebPage` — Default. Use when no other subtype fits.
- `AboutPage` — "About us", company history, team pages.
- `CollectionPage` — Index/listing pages: blog archives, project overviews, category listings.
- `ContactPage` — Contact information, office addresses, contact forms.
- `FAQPage` — Frequently asked questions. Google supports rich results for this type.
- `ItemPage` — A single item within a collection, e.g. a specific product or portfolio piece.
- `ProfilePage` — A person or organization profile. Google supports rich results for this type.
- `SearchResultsPage` — Pages displaying search results.

This is configurable per page in the admin under the Advanced tab.

For custom controllers without a page record, use `put_json_ld_type/2`:

```elixir
conn
|> put_json_ld_type("CollectionPage")
```

Every `put_json_ld/4` call also sets the page type, to the entry's
`json_ld_type` or `"WebPage"` when it has none. Call `put_json_ld_type/2`
after `put_json_ld/4`, or the entity call resets it.

### Identity type-specific fields

The Identity form includes type-specific fields that populate additional
schema.org properties based on the selected identity type:

| Type | Additional fields |
|------|-------------------|
| Person | `jobTitle`, `hasOccupation`, `additionalType`, `knowsAbout` — and none of the Organization properties |
| Organization, EducationalOrganization, GovernmentOrganization, NGO | `foundingDate`, `numberOfEmployees` |
| Corporation | `foundingDate`, `numberOfEmployees`, `tickerSymbol` |
| MedicalOrganization | `foundingDate`, `numberOfEmployees`, `medicalSpecialty` |
| SportsOrganization | `foundingDate`, `numberOfEmployees`, `sport` |
| ProfessionalService, Architect | `foundingDate`, `openingHoursSpecification`, `priceRange`, `geo` |
| LocalBusiness, ArtGallery, EmploymentAgency | `openingHoursSpecification`, `priceRange`, `geo` |
| Restaurant | `openingHoursSpecification`, `priceRange`, `servesCuisine`, `hasMenu`, `geo` |

Every type except Person also gets `legalName`, `vatID`, `areaServed` and
`knowsAbout`.

These are stored in the `type_config` embedded schema on Identity and
automatically included in the JSON-LD output.

A **Person** identity is for a site about one person. `additionalType` takes
a URL for a type schema.org doesn't have — an artist can point at Wikidata's
"visual artist" (`https://www.wikidata.org/wiki/Q3391743`) — and the
identity's links become `sameAs`.

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
