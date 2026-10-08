# JSON-LD

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

<!-- usage-rules:start topic="seo" -->

### Blueprint DSL

Define structured data fields for your blueprint's content type. The examples
refer to the schema modules through `alias Brando.JSONLD`:

```elixir
alias Brando.JSONLD

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
  field :mainEntityOfPage, :current_url
  field :url, :current_url
end
```

#### dateModified

Search and answer engines show `dateModified` as "Updated …", and compare it
with the sitemap's `lastmod`. Read it with `Brando.Blueprint.Value.modified_at/1`
rather than `updated_at`, which moves on every save, block re-render and
`mix brando.entries.resave`.

<!-- usage-rules:end -->

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

<!-- usage-rules:start topic="seo" -->

#### Field types

| Type | Description |
|------|-------------|
| `:identity` | Creates `{"@id": "hostname/#identity"}` reference to site identity |
| `:person` | A Brando user, a People entry, a name, or a list of them, as linked `Person` nodes (see [Authors](#authors)) |
| `:datetime` | Converts to ISO 8601 string |
| `:date` | Converts to `YYYY-MM-DD` string |
| `:duration` | Converts whole minutes, a `Duration` or `"HH:MM:SS"` to ISO 8601 (`90` is `"PT1H30M"`); an ISO 8601 duration is kept |
| `:image` | Builds an `ImageObject` with url, width, height |
| `:current_url` | Uses the page's current absolute URL |
| `:language` | Extracts the language from the entry or meta |
| `:string` | Direct string value via `value_fn` |
| `:integer` | Direct integer value via `value_fn` |
| `{:list, SchemaModule}` | Maps over a list, calling `SchemaModule.build/1` on each item |
| `SchemaModule` | Calls `SchemaModule.build/1` on the extracted value |

<!-- usage-rules:end -->

#### List type example

Map over a collection of items to build nested schema objects:

```elixir
json_ld_schema JSONLD.Schema.Event do
  field :name, :string, & &1.title
  field :startDate, :datetime, & &1.start_date
  field :performer, {:list, JSONLD.Schema.Person}, & &1.performers
end
```

<!-- usage-rules:start topic="seo" -->

### Authors

Map who wrote an entry with the `:person` field type. Nothing is emitted for
an author unless the blueprint maps one, so admin users never appear in
structured data by accident:

```elixir
alias Brando.JSONLD

json_ld_schema JSONLD.Schema.Article do
  # a Brando user: `trait :creator` gives every entry one
  field :author, :person, & &1.creator
end
```

<!-- usage-rules:end -->

or People entries, from a relation:

```elixir
field :author, :person, & &1.authors
```

<!-- usage-rules:start topic="seo" -->

The callback may return one value or a list, and anything not preloaded is
skipped (it never queries). Each author becomes its own `Person` node in the
`@graph`, and the field holds a reference to it:

```json
{"@type": "Article", "author": {"@id": "https://example.com/people/ada/#person"}, ...},
{"@type": "Person", "@id": "https://example.com/people/ada/#person", "name": "Ada Lovelace", ...}
```

<!-- usage-rules:end -->

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
- the videos in its block fields: each active ref with a video and each
  video variable, in active blocks and their children. A video block's title
  override names the video.

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
| `JSONLD.Schema.Product` | Product | A product for sale (see [Rich result types](#rich-result-types)) |
| `JSONLD.Schema.Offer` | Offer | A product's price, currency and availability |
| `JSONLD.Schema.AggregateRating` | AggregateRating | The average of many ratings |
| `JSONLD.Schema.Review` | Review | A review of a thing, or one of a product's reviews |
| `JSONLD.Schema.Rating` | Rating | A review's rating |
| `JSONLD.Schema.JobPosting` | JobPosting | A job opening |
| `JSONLD.Schema.MonetaryAmount` | MonetaryAmount | A job's salary |
| `JSONLD.Schema.Recipe` | Recipe | A recipe |
| `JSONLD.Schema.HowToStep` | HowToStep | One of a recipe's steps |
| `JSONLD.Schema.NutritionInformation` | NutritionInformation | A recipe's nutrition per serving |
| `JSONLD.Schema.Thing` | any type | Something Brando has no schema for: the book a review is about, the country a remote job is open to |
| `JSONLD.Schema.ImageObject` | ImageObject | Image metadata |
| `JSONLD.Schema.VisualArtwork` | VisualArtwork | An artwork, in a project's `hasPart` |

The identity schema is handled automatically from the identity type chosen in
the admin: Person, Organization, Corporation, ProfessionalService,
LocalBusiness, Restaurant, Architect, ArtGallery, EducationalOrganization,
EmploymentAgency, GovernmentOrganization, MedicalOrganization, NGO or
SportsOrganization.

### Controller usage

<!-- usage-rules:start topic="seo" -->

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

<!-- usage-rules:end -->

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

<!-- usage-rules:start topic="seo" -->

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

<!-- usage-rules:end -->

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

<!-- usage-rules:start topic="seo" -->

Every `put_json_ld/4` call also sets the page type, to the entry's
`json_ld_type` or `"WebPage"` when it has none. Call `put_json_ld_type/2`
after `put_json_ld/4`, or the entity call resets it.

<!-- usage-rules:end -->

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
defmodule MyApp.JSONLD.Schema.Course do
  @derive Jason.Encoder
  defstruct "@context": "https://schema.org",
            "@type": "Course",
            "@id": nil,
            name: nil,
            description: nil,
            provider: nil

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
json_ld_schema MyApp.JSONLD.Schema.Course do
  field :name, :string, & &1.title
  field :description, :string, & &1.description
  field :provider, :identity
end
```

A type that earns a rich result should get its rules in
`Brando.JSONLD.Rules`, so the inspector and Content SEO check it.

### Rich result types

These types earn their own results in Google Search. Each is a schema module
for `json_ld_schema`, with nested modules for its parts, and each is checked
against the properties listed here (see [Checking](#checking-structured-data)).
*Required* properties are errors when missing: Google shows no rich result
without them. *Recommended* ones are warnings.

#### Product and Offer

```elixir
json_ld_schema JSONLD.Schema.Product do
  field :name, :string, & &1.title
  field :description, :string, & &1.meta_description
  field :image, :image, & &1.cover
  field :sku, :string, & &1.sku

  field :offers, JSONLD.Schema.Offer, fn product ->
    %{price: product.price, price_currency: "NOK", availability: if(product.in_stock, do: :in_stock, else: :out_of_stock)}
  end

  field :aggregateRating, JSONLD.Schema.AggregateRating, &%{rating_value: &1.rating, review_count: &1.review_count}
  field :review, {:list, JSONLD.Schema.Review}, & &1.reviews
  field :url, :current_url
end
```

| Type | Required | Recommended |
|------|----------|-------------|
| [`Product`](https://developers.google.com/search/docs/appearance/structured-data/product-snippet) | `name`, and one of `offers`, `review` or `aggregateRating` | `image`, `description`, `sku` |
| [`Offer`](https://developers.google.com/search/docs/appearance/structured-data/merchant-listing) | `price`, `priceCurrency` (ISO 4217, such as `NOK`) | `availability` |
| [`AggregateRating`](https://developers.google.com/search/docs/appearance/structured-data/review-snippet) | `ratingValue`, and `ratingCount` or `reviewCount` | |

`Offer.build/1` takes `price` (a number, a string or a `Decimal`),
`price_currency`, `availability`, `price_valid_until` and `url`.
`availability` is any schema.org item availability, as an atom or string in
snake case (`:in_stock`, `"pre_order"`) or by name (`"InStock"`); it is
emitted as the URL Google reads, `https://schema.org/InStock`. A nested
`Review` takes a map with `:author` (a user, a People entry or a name),
`:rating`, `:date_published`, `:body` and `:name`.

#### JobPosting

```elixir
json_ld_schema JSONLD.Schema.JobPosting do
  field :title, :string, & &1.title
  field :description, :string, & &1.description
  field :datePosted, :date, & &1.publish_at
  field :validThrough, :datetime, & &1.deadline
  field :employmentType, :string, fn _ -> "FULL_TIME" end
  field :hiringOrganization, :identity
  field :jobLocation, JSONLD.Schema.Place, & &1.office
  field :baseSalary, JSONLD.Schema.MonetaryAmount, &%{currency: "NOK", min: &1.salary_from, max: &1.salary_to, unit: "YEAR"}
  field :url, :current_url
end
```

A remote job has no `jobLocation`; it says so, and where applicants may live:

```elixir
field :jobLocationType, :string, fn _ -> "TELECOMMUTE" end
field :applicantLocationRequirements, JSONLD.Schema.Thing, fn _ -> %{type: "Country", name: "NO"} end
```

| Required | Recommended |
|----------|-------------|
| `title`, `description` (HTML is allowed), `datePosted`, `hiringOrganization` (the site's identity with `:identity`), and `jobLocation` or `jobLocationType: "TELECOMMUTE"`; a remote job also needs `applicantLocationRequirements` | `validThrough`, `employmentType`, `baseSalary` |

`employmentType` is one or a list of `FULL_TIME`, `PART_TIME`, `CONTRACTOR`,
`TEMPORARY`, `INTERN`, `VOLUNTEER`, `PER_DIEM` and `OTHER`.
`MonetaryAmount.build/1` takes `currency`, a `value` or a `min` and `max`,
and the `unit` it is paid per (`HOUR`, `DAY`, `WEEK`, `MONTH`, `YEAR`).
Google's [job posting guide](https://developers.google.com/search/docs/appearance/structured-data/job-posting)
has the details.

#### Recipe

```elixir
json_ld_schema JSONLD.Schema.Recipe do
  field :name, :string, & &1.title
  field :description, :string, & &1.meta_description
  field :image, :image, & &1.cover
  field :author, :person, & &1.creator
  field :datePublished, :datetime, & &1.publish_at
  field :prepTime, :duration, & &1.prep_minutes
  field :cookTime, :duration, & &1.cook_minutes
  field :totalTime, :duration, &(&1.prep_minutes + &1.cook_minutes)
  field :recipeYield, :string, &"#{&1.servings} servings"
  field :recipeIngredient, :string, & &1.ingredients
  field :recipeInstructions, {:list, JSONLD.Schema.HowToStep}, & &1.steps
  field :nutrition, JSONLD.Schema.NutritionInformation, &%{calories: "#{&1.calories} calories"}
end
```

| Required | Recommended |
|----------|-------------|
| `name`, `image` | `author`, `datePublished`, `description`, `recipeIngredient`, `recipeInstructions`, `recipeYield`, `prepTime`, `cookTime`, `totalTime` (ISO 8601 durations), `recipeCategory`, `recipeCuisine`, `keywords`, `nutrition.calories`, `aggregateRating`, `video` |

Each step is its text, or a map with `:text`, `:name`, `:url` and `:image`.
The recipe's videos are described automatically, as for articles (see
[Videos](#videos)). See Google's [recipe guide](https://developers.google.com/search/docs/appearance/structured-data/recipe).

#### Review

```elixir
json_ld_schema JSONLD.Schema.Review do
  field :name, :string, & &1.title
  field :author, :person, & &1.creator
  field :datePublished, :datetime, & &1.publish_at
  field :reviewBody, :string, & &1.summary
  field :reviewRating, JSONLD.Schema.Rating, &%{rating_value: &1.rating, best_rating: 6, worst_rating: 1}
  field :itemReviewed, JSONLD.Schema.Thing, &%{type: "Book", name: &1.book_title}
  field :publisher, :identity
end
```

| Required | Recommended |
|----------|-------------|
| `author` with its `name`, `itemReviewed`, `reviewRating` with its `ratingValue` | `datePublished` |

Inside a `Product` or a `Recipe` the item reviewed is the product or recipe,
so a nested review may leave `itemReviewed` out. Give `bestRating` and
`worstRating` when the scale isn't 1 to 5. Google reads `itemReviewed` of
the types its [review snippet guide](https://developers.google.com/search/docs/appearance/structured-data/review-snippet)
lists: `Book`, `Course`, `Event`, `LocalBusiness`, `Movie`, `Product`,
`Recipe`, `SoftwareApplication` and a few more.

### Checking structured data

`Brando.JSONLD.Rules` holds Google's required and recommended properties for
every type with a rich result, as data, with the page each rule comes from:
`Article` (and `NewsArticle`, `BlogPosting`), `Product`, `Offer`,
`AggregateRating`, `Review`, `JobPosting`, `Recipe`, `VideoObject`,
`BreadcrumbList`, `Organization` (and its subtypes), `LocalBusiness` (and its
subtypes), `Person`, `ProfilePage` and `Event`.

A missing required property is an **error**. A missing recommended property
is a **warning**, as is a value Google can't read: a date that isn't ISO
8601, a relative URL where an absolute one is needed, an empty name or
headline, a duration that isn't ISO 8601, or a value outside the type's
vocabulary (an availability, an employment type). Paths such as
`author.name` are followed through `@id` references to the linked node.

```elixir
Brando.JSONLD.Rules.validate(%{"@type" => "Recipe", "name" => "Waffles"})
#=> [%{level: :error, property: "image", kind: :missing}, ...]
```

#### The inspector

An entry's Meta drawer has a **Structured data** tab for blueprints with a
`json_ld_schema`. It shows the graph the entry's page emits, built by
`Brando.JSONLD.Graph.for_entry/3` the way the [controller
example](#adding-a-content-entity) builds it: `put_title/2` with the
entry's title, `put_breadcrumbs/2` for stored breadcrumbs, and
`put_json_ld/3`. It reads the entry with what its mapping reads (the
associations its callbacks use, a user's avatar, its video fields and the
videos in its blocks). A controller that adds more, or preloads less, emits
a different graph.

- Each entity is a node with its type and `@id`. Edges are labelled with the
  property that links them (`publisher`, `isPartOf`, `author`, `video`,
  `mainEntityOfPage`…).
- A node Google would flag has an amber border (a red one for errors) and a
  count.
- A dashed node is what the page would gain: an author the blueprint doesn't
  map or the entry doesn't have, an image, a video.
- Selecting a node lists its properties and where each comes from: an
  entry field (`title`; `meta_description → intro` for a fallback), the
  identity, the page URL, or `computed`. Required and recommended properties
  that aren't mapped say so. The mapping is read-only: it lives in the
  blueprint.
- **Copy JSON-LD** copies the content of the page's
  `<script type="application/ld+json">`; **Rich Results Test** opens
  Google's test for the page's public URL, for published entries with a page.

Content SEO (Configuration → SEO → Content SEO) counts the published entries
of every such blueprint with errors and with warnings, and links each to its
inspector. Only the nodes that describe the entry count, not the site's
identity, which every page shares. The check builds every entry's graph
without its blocks, so videos in blocks are not counted there; it runs when
the tab opens and is kept for ten minutes, and **Run again** checks again.

The E2E data is checked in a few milliseconds; 2,000 projects with authors
and cover videos took about half a second on a laptop.
