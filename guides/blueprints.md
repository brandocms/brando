# Blueprints

A Blueprint declares one content type: its fields, how entries are named and
linked to, its traits, and its admin listing and form. `use Brando.Blueprint`
turns the declaration into an Ecto schema with a generated `changeset/5`,
storage that [Blueprint migrations](blueprint_migrations.md) can generate, and
the metadata the admin and the rest of Brando read. Declarations are checked
while the Blueprint compiles, so most mistakes fail the build instead of a
request.

Generate a new content type with `mix brando.gen.blueprint Catalog Product`;
see [Installation and generators](generators.md#generate-a-content-type).
Keep the Blueprint, its generated migrations and its migration snapshots under
version control.

<!-- usage-rules:start -->

## A Blueprint

```elixir
defmodule MyApp.Articles.Article do
  use Brando.Blueprint,
    application: "MyApp",
    domain: "Articles",
    schema: "Article",
    singular: "article",
    plural: "articles"

  import Brando.Blueprint.Listings.Components.Core

  content_icon "newspaper"

  trait :creator
  trait :status
  trait :timestamped

  identifier ~H"{@entry.title}"
  absolute_url ~H"/articles/{@entry.slug}"

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true, unique: [prevent_collision: true]
    attribute :introduction, :text
  end

  relations do
    relation :category, :belongs_to, module: MyApp.Articles.Category
  end

  assets do
    asset :cover, :image, cfg: :default
  end

  listings do
    listing do
      query %{order: [{:desc, :inserted_at}]}
      filter label: t("Title"), key: "title"
      component &__MODULE__.listing_row/1
    end
  end

  forms do
    form do
      default_params %{"status" => "draft"}

      tab t("Content") do
        fieldset do
          input :status, :status
          input :title, :text, label: t("Title")
          input :slug, :slug, source: :title, label: t("Slug")
          input :introduction, :textarea, label: t("Introduction")
          input :cover, :image, label: t("Cover")
        end
      end
    end
  end

  translations do
    context :naming do
      translate :singular, t("article")
      translate :plural, t("articles")
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.update_link entry={@entry} columns={10}>{@entry.title}</.update_link>
    <.url entry={@entry} />
    """
  end
end
```

<!-- usage-rules:end -->

A Blueprint is used together with a context built on `Brando.Query`
([Querying](querying.md)) and two admin LiveViews, which
`mix brando.gen` writes.

The parts are documented in these guides:

* [Attributes, relations, and assets](blueprint_fields.md): fields, uniqueness,
  constraints, associations and media.
* [Traits](blueprint_traits.md): status, ordering, soft deletion, translation
  and the other built-in traits, and how to write your own.
* [Blueprint listings](blueprint_listings.md): the admin listing, its filters,
  sorts, actions and exports.
* [Blueprint forms](blueprint_forms.md): the admin form, its inputs and
  subforms.
* [Blueprint migrations](blueprint_migrations.md): generating storage
  changes.
* [Datasources](datasources.md), [Page metadata](meta.md) and
  [JSON-LD](jsonld.md): the sections that feed modules and page heads.
* [Groups and authorization](authorization.md): the `authorization`
  declaration.

This guide covers the rest: the root declaration, schema settings,
identifiers, URLs, translations and the generated changeset.

<!-- usage-rules:start -->

## Declaring a Blueprint

```elixir
use Brando.Blueprint,
  application: "MyApp",
  domain: "Articles",
  schema: "Article",
  singular: "article",
  plural: "articles",
  gettext_module: MyAppAdmin.Gettext,
  router_scope: :editorial,
  extensions: [MyApp.BlueprintExtension]
```

Write the options as literals; module attributes are not available yet.

* `application`, `domain`, `schema` (required): PascalCase module segments.
  Brando derives conventional module names from them: the context
  `MyApp.Articles`, and the admin views `MyAppAdmin.Articles.ArticleListLive`
  and `ArticleFormLive`.
* `singular`, `plural` (required): snake_case names. They name the context
  functions (`get_article`, `list_articles`) and admin route helpers, and are
  the fallback labels in the admin.
* `gettext_module`: the Gettext backend for `t/1` and admin labels. Default
  `<application>Admin.Gettext`, such as `MyAppAdmin.Gettext`, which must
  exist when the Blueprint compiles.
* `router_scope`: an atom or string that admin route helpers include, for
  admin routes declared in a named scope. With `router_scope: :editorial`, the
  listing uses `admin_editorial_live_path` and the form
  `admin_editorial_article_form_path`.
* `extensions`: more Spark extensions for the Blueprint DSL, such as a JSON
  API or GraphQL extension.

<!-- usage-rules:end -->

Unknown, duplicate or missing options, and malformed names, fail before
anything else compiles.

`use Brando.Blueprint` imports `Ecto.Changeset`, `Phoenix.Component` (except
`form/1`), Gettext, `t/1` and `t/2`, the metadata helpers, and the DSL. It
does not import `Ecto.Query`.

## Schema settings

These go in the Blueprint body:

```elixir
table "editorial_articles"
data_layer :database
primary_key :id
factory %{status: :draft}
content_icon "newspaper"
```

* `table`: the table name, in snake_case. Default `<plural>` when the domain
  and plural are the same word, otherwise `<domain>_<plural>` with the domain
  lowercased: `articles` for the example above, `catalog_products` for a
  `Catalog` domain, and `blogposts_posts` for a `BlogPosts` domain. Changing it on an existing table needs a hand-written
  migration; see [Changes that require a hand-written
  migration](blueprint_migrations.md#changes-that-require-a-hand-written-migration).
* `data_layer`: `:database` (the default) or `:embedded`, for a schema
  stored inside another entry through `embeds_one` or `embeds_many`. An
  embedded Blueprint has no table, migrations, context functions or
  identifier.
* `primary_key`: `:id` (the default, an integer), `:uuid` (`binary_id`), or
  `false` for no generated key, as on join schemas whose foreign keys form
  the key. A `{:id, type, options}` tuple may add a physical `source:`. Other
  names and layouts are rejected, because generated relations and migrations
  rely on them.
* `factory`: a map merged into the attributes passed to `__factory__/1`,
  for test factories.
* `content_icon`: the content type's [Lucide](https://lucide.dev/icons)
  icon, shown in the admin menu, link picker, identifiers and listing header
  (`@page_icon`). An unknown name fails to compile, and a renamed one names
  its replacement. Default `"file"`. `Brando.Blueprint.get_icon/1` returns
  it. The macro is `content_icon/1`, so a Blueprint can still import an
  `icon/1` component for its rows.
* `@allow_mark_as_deleted true`: for schemas edited as nested entries, such
  as the join schema of a multi-select. When the changeset receives
  `marked_as_deleted: true`, a stored entry gets Ecto's `:delete` action and
  an unsaved one is ignored, and no field is validated, so values on an entry
  being removed cannot make its parent invalid. It adds a virtual
  `marked_as_deleted` field. Embedded Blueprints have it on.
* `authorization`: the permission key, extra actions and policy for the
  schema. See [Groups and authorization](authorization.md#resource-metadata-and-policies).

Every Blueprint exports a struct type `t/0`. Declare your own `@type t` for a
more precise one; Blueprint keeps it.

<!-- usage-rules:start -->

## Identifier

An identifier is how an entry is named across the admin: in selects,
multi-selects, `:entries` pickers, the link picker, and the persisted
identifier records those use.

```elixir
identifier ~H"{@entry.title}"
identifier ~H"{@entry.title} [{@entry.category.name}]"

# Liquex
identifier "{{ entry.title }} [{{ entry.category.name }}]"
```

The template receives the entry as `@entry` in HEEx and `entry` in Liquex.
The result is trimmed. Associations it reads, such as `category`, are
collected in `__identifier_preloads__/0` and preloaded when identifiers are
built, so declare them as relations.

`identifier false` (or `nil`) turns identifiers off. Without an `identifier`
declaration the Blueprint has none. Embedded Blueprints cannot have one: an
identifier template after `data_layer :embedded` fails to compile. Leave
`identifier` out of them, or write `identifier false`.

<!-- usage-rules:end -->

Identifiers are stored in Brando's identifier table so other entries can point
at them, as `:entries` relations, the link picker and content transfer do.
`persist_identifier false` keeps a Blueprint's identifiers out of that
table: they are still built for selects, but entries of the schema cannot be
picked in those places.

The fields the identifier shows are also the only required fields of a
[draft](#drafts).

Invalid template syntax fails the compilation with the parser's location.

<!-- usage-rules:start -->

## Absolute URL

`absolute_url` declares an entry's public URL. Admin preview links, SEO
checks, sitemaps, hreflang alternates, identifiers, permalink redirects and
`<.url>` listing links use it.

```elixir
# Localized route for a translatable entry
absolute_url ~H|{route_i18n(@entry, :article_path, :detail, [@entry.slug])}|

# Non-localized route
absolute_url ~H|{route(:article_path, :detail, [@entry.slug])}|

# Static path
absolute_url ~H"/articles/{@entry.slug}"

# Liquex
absolute_url "/articles/{{ entry.slug }}"

# No public URL
absolute_url false
```

`route(helper, action, args)` calls the router helper with the endpoint.
`route_i18n(entry, helper, action, args)` builds the localized path for the
entry's `language`. For `:page_path` with `:show`, both split each argument
on `/`, and `route_i18n` prefixes the language itself (leaving it out for
the default language when `scope_default_language_routes` is `false`). Use
`route_i18n` for schemas with a `language` field whose routes are localized,
and `route` otherwise.

<!-- usage-rules:end -->

Associations the template reads are collected in
`__absolute_url_preloads__/0`. The SEO audit, permalink redirects and
translation links preload them; elsewhere, preload them before calling
`__absolute_url__/1`, for instance in a listing's `query` or a sitemap query.
A static path such as `/articles/{@entry.slug}` needs none.
With a HEEx template, `__absolute_url__/1` returns `nil` when building the
URL fails because a route does not exist or an argument is missing, rather
than raising. `Brando.Blueprint.URL.resolve/1` calls it for any entry, and
`resolve(entry, :with_host)` adds the endpoint's host.

The tuple form `absolute_url {:i18n, :article_path, :detail, [:slug]}` still
compiles, with a deprecation warning; use HEEx with `route_i18n`.

<!-- usage-rules:start -->

### Only some entries have a URL

When only some entries have a page on the site, such as a case that only
links to the client or a page that is just a section, declare which ones with
`only:`. A map lists fields and the values they must equal:

```elixir
absolute_url ~H"/projects/{@entry.slug}", only: %{type: :full_case}
```

Brando's `Page` uses `only: %{has_url: true}`, so pages with **Has URL** off
have none. The declaration answers two questions:

* `__has_url__/1`: whether an entry has a URL on this site.
* `__url_filter__/0`: the same map, to pass as a list query's `filter:` so
  such entries are never loaded, as in a sitemap:
  `filter: Project.__url_filter__()`. The context needs filter clauses for
  those keys.

<!-- usage-rules:end -->

For the entries `only:` excludes, `__absolute_url__/1` returns `nil`. Sitemaps
skip them (with a warning suggesting the query filter), the SEO audit leaves
them out, hreflang alternates omit them, and no permalink redirect is
proposed. An external link stored on the entry is content, not the entry's
URL.

`only:` also takes a one-arity function for rules that are not plain equality.
It answers `__has_url__/1` only; `__url_filter__/0` is then `nil`, because a
function cannot become a query:

```elixir
absolute_url ~H"/projects/{@entry.slug}", only: &(&1.external_url in [nil, ""])
```

Without `only:`, every entry has a URL and `__url_filter__/0` is `nil`.
`absolute_url false` takes no options.

## Content transfer matching

Blueprints with block fields and persisted identifiers appear in
[Content import and export](content_transfer.md). To suggest matching entries
across installations, define a stable, JSON-safe key without database IDs:

```elixir
require Ecto.Query

def content_transfer_key(entry), do: %{"slug" => entry.slug, "language" => to_string(entry.language)}

def content_transfer_query(%{"slug" => slug, "language" => language}) do
  Ecto.Query.from(entry in __MODULE__, where: entry.slug == ^slug and entry.language == ^language)
end
```

Import checks the returned key and applies the destination's authorization to
query results. `content_transfer_query/1` is optional; provide it on large
tables so suggestions don't scan every entry. Matching only suggests a
target: the editor still chooses the destination and block field. Pages and
fragments have built-in keys and queries.

<!-- usage-rules:start -->

## Translations

```elixir
translations do
  context :naming do
    translate :singular, t("article")
    translate :plural, t("articles")
  end
end
```

`translations` holds strings the admin looks up by context and key.
`[:naming, :singular]` and `[:naming, :plural]` name the content type in the
menu, listings and pickers; `Brando.Blueprint.get_singular/1` and
`get_plural/1` read them, falling back to the `use` options. Context names
must be unique, and keys unique within a context. `__translations__/0`
returns them translated into the current locale.

`t("text")` marks a string for extraction into the Blueprint's Gettext
domain, `<domain>_<schema>` in lowercase (`articles_article`). Labels in
listings and forms are translated in that domain when they render. `t("text",
OtherSchema)` uses another Blueprint's domain, as for a subform's labels; it
reads that Blueprint's naming while compiling, so it makes this Blueprint
compile against the other one.

<!-- usage-rules:end -->

## Datasources, metadata, and JSON-LD

These sections are covered in their own guides; here are their rules.

```elixir
datasources do
  datasource :featured do
    type :selection
    list &__MODULE__.featured_choices/3
    get &__MODULE__.featured_entries/1
  end
end
```

A `datasource` has an atom key and a `type`: `:list` needs `list`,
`:selection` needs `list` and `get`, and `:single` needs `get`. `list`
receives the module, language and module variables; `get` receives the
selected identifiers. Both return `{:ok, results}`. `meta key, type, label:
"..."` declares extra fields editors fill in for a selection. Keys must be
unique. Callbacks may also be `{module, function, extra_args}` tuples; the
runtime arguments come first and each element of `extra_args` is appended as
a further argument, so `{MyApp.Articles, :list_featured, [:published]}` calls
`list_featured(module, language, vars, :published)`. See
[Datasources](datasources.md).

`meta_schema` maps entry fields to page metadata targets, and
`json_ld_schema` maps them to a JSON-LD entity. A Blueprint has at most one
of each. Metadata targets are non-empty strings. JSON-LD fields must exist on
the schema struct, value types need a callback and derived types
(`:current_url`, `:identity`, `:language`) must not have one, and nested
schema modules must export `build/1`. The `:person` type maps users and
People entries to `Person` nodes and needs a callback too. `videos false`
inside a `json_ld_schema` turns off the automatic `VideoObject`s. See
[Page metadata](meta.md) and [JSON-LD](jsonld.md).

The imported metadata helpers `fallback/2` and `try_path/2` follow paths
through maps, structs, keyword lists and list indexes, such as
`[:settings, :seo, :images, 0, "url"]`. A step that does not match returns
`nil` instead of raising, so the next fallback is tried; `false`, `0` and `""`
are values, not missing data.

## The changeset

Every database Blueprint gets:

```elixir
changeset(entry, params \\ %{}, user \\ :system, sequence \\ nil, opts \\ [])
```

It runs, in order:

1. `cast/3` of the attributes, belongs-to foreign keys and image, file and
   video `_id` fields;
2. relations with `cast: true`, embeds, galleries and `:entries` relations;
3. block fields, only when `opts` has `cast_blocks: true` (the admin's
   block editor saves blocks itself);
4. the `changeset_mutator` of traits that run before validation, such as
   `trait :creator`;
5. `validate_required/2` of required attributes, relations and assets, or
   the [draft](#drafts) subset;
6. unique constraints, then `constraints:` validations, then foreign-key
   constraints for belongs-to relations;
7. the other traits' `changeset_mutator`;
8. with `trait :sequenced` and a `sequence`, setting the sequence;
9. rich-text validation.

`user` is the current user, or `:system` for work done by Brando or a job.
Traits use it to stamp creators and editors, and relation casts pass it on.

<!-- usage-rules:start -->

### Drafts

When `status` is `:draft`, the changeset only requires the required fields
the [identifier](#identifier) shows, usually the title. A draft can be saved
half done, but never without the name it is listed by. Collision handling for
unique fields is also skipped for drafts.

### Custom changesets

Write extra changeset functions for other subsets of fields, and pass them to
a mutation:

```elixir
def name_changeset(entry, params, _user \\ :system) do
  entry
  |> cast(params, [:name])
  |> validate_required([:name])
end
```

```elixir
MyApp.Articles.update_article(id, %{"name" => "New name"}, user,
  changeset: &MyApp.Articles.Article.name_changeset/3
)
```

<!-- usage-rules:end -->

<!-- usage-rules:start -->

## Compile-time checks

Brando checks a Blueprint in three stages:

* `use Brando.Blueprint` checks its options.
* While the module compiles, Brando checks the root settings, every
  attribute, relation and asset with their options and constraints,
  uniqueness scopes, duplicate field and column names, asset configs,
  identifier and URL templates, datasources, metadata, translations and
  listings. A failure stops the compilation with a `Spark.Error.DslError` or
  `Brando.Exception.BlueprintError` naming the section and entry.
* After the module compiles, Brando checks forms, which need the related
  schemas compiled, and runs each trait's `validate/2`. Form errors are
  printed as **warnings** and the module still compiles; trait validation
  errors raise. Build with `mix compile --warnings-as-errors` so form
  mistakes fail too.

The checks need no database. Fix declarations reported after an upgrade; if
a fix changes stored columns, follow [Blueprint migrations](blueprint_migrations.md).

<!-- usage-rules:end -->

## Introspection

Generated functions that application code can call:

* `__naming__/0`: application, domain, schema, singular, plural, table name
  and id.
* `__modules__/0` and `__modules__/1`: the conventional context, schema,
  Gettext and admin view modules.
* `__admin_route__/2`: the admin path for `:list`, `:create` or `:update`
  (with the ID).
* `__absolute_url__/1`, `__has_absolute_url__/0`, `__has_url__/1`,
  `__url_filter__/0` and `__absolute_url_preloads__/0`.
* `__identifier__/1`, `__has_identifier__/0` and `__persist_identifier__/0`.
* `has_trait/1`, `__trait__/1` and `__traits__/0`; see [Traits](blueprint_traits.md).
* `has_status?/0`, `__slug_fields__/0`, `__status_fields__/0`,
  `__image_fields__/0`, `__file_fields__/0`, `__video_fields__/0`,
  `__gallery_fields__/0` and `__blocks_fields__/0`.
* `__listings__/0`, `__forms__/0` and `__form__/1`.
* `__translations__/0`, `__data_layer__/0` and `__factory__/1`.

For fields, `__attributes__/1` in `Brando.Blueprint.Attributes`,
`Brando.Blueprint.Relations.__relations__/1` and
`Brando.Blueprint.Assets.__assets__/1` list them;
`Brando.Blueprint.preloads_for/2` returns the preloads for a complete entry.
`Brando.Blueprint.list_blueprints/0` lists the application's Blueprints.

<!-- usage-rules:start -->

## Deprecated declarations

These still compile but only print a warning; what they declare is dropped.
`mix brando.migrate54` rewrites them:

* `listing_query/1` and `form_query/1`: use `query`.
* `filters/1` and `actions/1,2`: use `filter`, `action` and
  `default_actions`.
* `field/3` and `template/2` in listings: use a row `component`.
* `inputs_for/3`, including `inputs_for :name, opts do ... end`: write the
  options inside the block.

Datasources' top-level `list/2`, `single/2` and `selection/3` compile to
nothing; use `datasource` entries.

<!-- usage-rules:end -->

## Module definitions

Content modules can also be written as declarative definitions and exported
from the admin to the same format. See
[Module definitions as files](module_definitions.md).
