# Querying

`Brando.Query` is the public query and mutation API for Brando contexts. It
generates conventional context functions, applies a shared set of query options,
and keeps Blueprint-aware concerns such as revisions, soft deletion, caching,
and mutation lifecycle handling in one place.

Use the generated context functions from application code. The lower-level
helpers are useful when composing an Ecto query yourself, but the compiler and
runtime modules behind `Brando.Query` are internal implementation details.

## Defining a context

A context declares its list query, single-entry query, accepted filters and
matches, and mutations:

```elixir
defmodule MyApp.Projects do
  use Brando.Query

  import Ecto.Query

  alias MyApp.Projects.Project

  query :list, Project do
    fn query -> from(project in query) end
  end

  filters Project do
    fn
      {:featured, featured}, query ->
        from project in query, where: project.featured == ^featured

      {:search, search}, query ->
        pattern = "%#{Brando.Query.sanitize_ilike_pattern(search)}%"
        from project in query, where: ilike(project.title, ^pattern)

      {:category_id, category_id}, query ->
        from project in query, where: project.category_id == ^category_id
    end
  end

  query :single, Project do
    fn query -> from(project in query) end
  end

  matches Project do
    fn
      {:id, id}, query ->
        from project in query, where: project.id == ^id

      {:slug, slug}, query ->
        from project in query, where: project.slug == ^slug
    end
  end

  mutation :create, Project
  mutation :update, Project
  mutation :delete, Project
end
```

The function names come from the Blueprint's singular and plural naming. For a
`Project` Blueprint, this generates:

```elixir
MyApp.Projects.list_projects(args \\ %{})
MyApp.Projects.list_projects!(args \\ %{})
MyApp.Projects.get_project(id_or_args)
MyApp.Projects.get_project!(id_or_args)
```

The non-bang functions return `{:ok, result}` or an error tuple. The bang
functions return the result and raise when a single entry does not exist.

Passing an ID directly is convenient when no query options are needed:

```elixir
{:ok, project} = MyApp.Projects.get_project(project_id)
```

Use a map with `matches` when selecting by another field or combining the match
with options:

```elixir
{:ok, project} =
  MyApp.Projects.get_project(%{
    matches: %{slug: "new-library"},
    include: [:category]
  })
```

## Query options

List and single-entry functions share the options that make sense for both
operations. List queries additionally support filtering, ordering, joins,
offsets, and pagination; single queries use `matches` and can retrieve a
revision.

| Option | Query | Purpose |
| --- | --- | --- |
| `filter` | list | Apply the context's `filters` clauses |
| `matches` | single | Apply the context's `matches` clauses |
| `select` | both | Return only selected fields |
| `order` | list | Apply one or more ordering expressions |
| `limit`, `offset` | list | Limit or offset results |
| `paginate` | list | Return entries together with pagination metadata |
| `status` | both | Filter a schema with a status field |
| `language`, `exclude_language` | both | Include or exclude languages |
| `join` | list | Left join associations |
| `preload` | both | Use the established low-level preload API |
| `include` | both | Recursively load associations with per-node options |
| `with_deleted` | both | Include soft-deleted entries |
| `revision` | single | Retrieve a stored revision by number |
| `cache` | both | Cache the result |

Unknown top-level options are rejected by the query reducer rather than being
silently ignored.

## Filtering and matching

`filter` accepts a map and reduces every entry through the clauses declared by
`filters`:

```elixir
{:ok, projects} =
  MyApp.Projects.list_projects(%{
    filter: %{featured: true, category_id: category.id}
  })
```

`matches` does the same for a single-entry query:

```elixir
{:ok, project} =
  MyApp.Projects.get_project(%{
    matches: %{slug: "new-library"}
  })
```

Add a clause for every supported key. An unknown key raises a
`Brando.Exception.QueryFilterClauseError` or
`Brando.Exception.QueryMatchClauseError`, which makes an accidental or stale
filter visible immediately.

When user input is used in `LIKE` or `ILIKE`, escape wildcard characters before
adding your own wildcard pattern:

```elixir
escaped = Brando.Query.sanitize_ilike_pattern(search)
pattern = "%#{escaped}%"

from project in query, where: ilike(project.title, ^pattern)
```

Contexts using `Brando.Query` also import `jsonb_contains/3`, and can use
`jsonb_contains_any_value_ilike/2` for case-insensitive matching against any
value in a JSON object:

```elixir
from project in query,
  where: jsonb_contains(project, :colors, [%{hex_value: color}])

from project in query,
  where: jsonb_contains_any_value_ilike(project.labels, label)
```

## Selecting fields

Without `select`, queries return complete schema structs. A list of fields
returns maps:

```elixir
{:ok, projects} =
  MyApp.Projects.list_projects(%{
    select: [:id, :title, :slug]
  })

# [%{id: 1, title: "New library", slug: "new-library"}, ...]
```

The explicit map form is equivalent:

```elixir
select: {:map, [:id, :title, :slug]}
```

Use the struct form when downstream code needs the schema type:

```elixir
select: {:struct, [:id, :title, :slug]}
```

Fields omitted from a partially selected struct retain their unloaded or
default values. When an association is included, its required relationship keys
must be selected too; see [Selecting association keys](#selecting-association-keys).

## Ordering

`order` accepts the same forms wherever Brando applies ordering: at the root of
a list query and inside an `include` node.

Use tuples or a keyword list in application code:

```elixir
order: [asc: :title, desc: :inserted_at]

# Equivalent tuple form
order: [{:asc, :title}, {:desc, :inserted_at}]
```

The compact string form is useful for Blueprint listing configuration and other
controlled values:

```elixir
order: "asc title, desc inserted_at"
```

Ordering through one or two associations is supported:

```elixir
order: [asc: {:category, :title}]
order: [asc: {:category, :parent, :title}]

# String equivalents
order: "asc category.title"
order: "asc category.parent.title"
```

Order strings are converted to atoms. Do not pass arbitrary, unbounded request
values directly; validate them against the sort choices your application
supports.

## Pagination

Set `paginate: true` together with a `limit`. `offset` defaults to zero:

```elixir
{:ok, result} =
  MyApp.Projects.list_projects(%{
    order: [desc: :inserted_at],
    paginate: true,
    limit: 20,
    offset: 40
  })

result.entries
result.pagination_meta.total_entries
result.pagination_meta.total_pages
result.pagination_meta.current_page
result.pagination_meta.next_offset
result.pagination_meta.previous_offset
```

Pagination counts the filtered query without its preload, order, limit, or
offset. Omitting `limit` while pagination is enabled raises an error.

## Status, language, and soft deletion

Schemas with a status field can use the conventional Brando status filters:

```elixir
status: :published
status: :published_and_pending
status: :all
```

Language filters accept either one language or a list:

```elixir
language: "en"
language: ["en", "no"]
exclude_language: "de"
```

For Blueprints using `Brando.Trait.SoftDelete`, deleted entries are excluded by
default. Include live and deleted entries with `with_deleted: true`, or request
only deleted entries with `status: :deleted`:

```elixir
MyApp.Projects.list_projects(%{with_deleted: true})
MyApp.Projects.list_projects(%{status: :deleted})
```

## Loading associations

Brando has two association-loading APIs:

- `preload` is the established, low-level API and remains backwards compatible.
- `include` is association-aware, recursive, and provides a uniform place for
  field selection, ordering, nesting, and custom queries.

Use `preload` when an existing call already expresses the query clearly or when
you need a raw Ecto preload shape. Use `include` when you want Brando to infer
the associated schema and configure the association as a query node.

### Preload

Simple and nested Ecto preloads work as before:

```elixir
preload: [:category, creator: :avatar]
```

An association can be loaded through a join:

```elixir
preload: [category: :join]
```

Ordered preload queries can use the established tuple form or an Ecto query:

```elixir
preload: [comments: {MyApp.Projects.Comment, [desc: :inserted_at]}]

comments_query =
  from comment in MyApp.Projects.Comment,
    where: is_nil(comment.deleted_at),
    order_by: [desc: comment.inserted_at]

MyApp.Projects.list_projects(%{
  preload: [comments: comments_query]
})
```

The configuration-map form is also available for legacy or specialized
preloads:

```elixir
preload: [
  comments: %{
    module: MyApp.Projects.Comment,
    order: [desc: :inserted_at],
    preload: [creator: :avatar],
    hide_deleted: true
  }
]
```

### Include

A plain association name loads the full related schema:

```elixir
include: [:category, :creator]
```

Each association can instead have an option map or keyword list:

| Include option | Purpose |
| --- | --- |
| `select` | Select fields from the related schema |
| `order` | Order with the same syntax as a root list query |
| `include` | Recursively include related associations |
| `query` | Start from a custom Ecto query for the inferred schema |

For example:

```elixir
{:ok, projects} =
  MyApp.Projects.list_projects(%{
    select: {:struct, [:id, :title]},
    include: [
      category: [
        select: [:id, :title]
      ],
      comments: [
        select: [:id, :project_id, :creator_id, :body, :inserted_at],
        order: "desc inserted_at",
        include: [
          creator: [select: [:id, :name]]
        ]
      ]
    ]
  })
```

The schema for `category`, `comments`, and `creator` is inferred from each
parent schema. Includes work on list queries, safe single queries, and bang
single queries. They also work with map selections: Brando adds the included
association to the projected map automatically.

Includes are validated when the query is built. Misspelled associations,
unsupported node options, duplicate associations, a query for the wrong schema,
and conflicting `preload`/`include` configuration produce an `ArgumentError`
with the relevant association name.

### Selecting association keys

Ecto needs the relationship keys on both sides of an association to attach
preloaded results. When using partial selections, keep those keys in every
relevant node.

For a `has_many :comments` association, the parent selection needs its `:id`
and the comment selection needs `:project_id`:

```elixir
select: {:struct, [:id, :title]},
include: [
  comments: [select: [:id, :project_id, :body]]
]
```

For `belongs_to :category`, the parent selection needs `:category_id`:

```elixir
select: {:struct, [:id, :title, :category_id]},
include: [
  category: [select: [:id, :title]]
]
```

Nested includes follow the same rule at every level. Brando reports a missing
parent-side key while building the query; Ecto also requires the related-side
key when loading the association.

### Custom include queries

Use `query` for association-specific filtering or joins that do not belong in
the context's root filter set:

```elixir
comments_query =
  from comment in MyApp.Projects.Comment,
    where: comment.approved == true

MyApp.Projects.list_projects(%{
  include: [
    comments: [
      query: comments_query,
      select: [:id, :project_id, :creator_id, :body],
      order: [desc: :inserted_at],
      include: [creator: [select: [:id, :name]]]
    ]
  ]
})
```

The custom query must be backed by the schema inferred for that association. If
the custom query already has a `select`, do not also specify the include node's
`select`; Brando rejects the ambiguous combination.

The same association cannot be configured through both `preload` and `include`
in one query. Disjoint associations can use the two APIs together:

```elixir
%{
  preload: [:category],
  include: [comments: [order: [desc: :inserted_at]]]
}
```

## Caching

Set `cache: true` for the default 15-minute TTL, or provide an explicit TTL in
milliseconds:

```elixir
MyApp.Projects.list_projects(%{
  status: :published,
  cache: true
})

MyApp.Projects.get_project(%{
  matches: %{slug: "new-library"},
  cache: {:ttl, :timer.minutes(5)}
})
```

The complete query argument map is part of the cache key. Generated Brando
mutations and the `Brando.Query.insert/2`, `update/2`, and `delete/1` helpers
evict affected query entries. Direct `Brando.Repo` writes do not automatically
evict this cache.

Do not combine cached list queries with pagination or streaming. Cached list
results are materialized as a plain list.

## Revisions

A safe single query can retrieve a stored revision when the match contains the
entry ID:

```elixir
{:ok, project} =
  MyApp.Projects.get_project(%{
    matches: %{id: project_id},
    revision: 2
  })
```

Revision numbers are zero-based. A missing revision is returned as the same
context-level not-found error used for a missing entry.

## Streaming

Generated list functions accept a second argument that enables an Ecto stream.
Consume it inside a repository transaction:

```elixir
Brando.Repo.transaction(fn ->
  stream =
    MyApp.Projects.list_projects(
      %{status: :published, select: [:id, :slug]},
      :stream
    )

  Enum.each(stream, &export_project/1)
end)
```

Use the non-bang list function for streaming. It returns the stream directly,
not an `{:ok, stream}` tuple. Do not combine streaming with query caching or
pagination.

## Mutations

`Brando.Query` also generates conventional context mutations:

```elixir
mutation :create, Project
mutation :update, Project
mutation :delete, Project
mutation :duplicate,
  {Project,
   change_fields: [:title],
   delete_fields: [:comments],
   merge_fields: %{contributors: []}}
```

The resulting functions accept the acting user so Brando can run the Blueprint
changeset and its lifecycle consistently:

```elixir
{:ok, project} = MyApp.Projects.create_project(params, current_user)

{:ok, project} =
  MyApp.Projects.update_project(project.id, update_params, current_user)

{:ok, project} = MyApp.Projects.delete_project(project.id, current_user)

{:ok, copy} =
  MyApp.Projects.duplicate_project(project.id, current_user)
```

Create and update also accept an `Ecto.Changeset`. Delete defaults the user to
`:system` when omitted. Mutation declarations can configure preloads, which are
useful when an identifier or lifecycle callback depends on associations:

```elixir
mutation :update, {Project, preload: [:category]}
```

Create, update, and delete declarations can run a callback after the mutation:

```elixir
mutation :update, Project do
  fn project ->
    MyApp.ProjectNotifier.updated(project)
    {:ok, project}
  end
end
```

## Composing queries directly

The public helpers can be used without a generated context function when a
caller needs to keep building an Ecto query:

```elixir
query =
  Project
  |> Brando.Query.with_status(:published)
  |> Brando.Query.with_language("en")
  |> Brando.Query.with_order([desc: :inserted_at])
  |> Brando.Query.with_select([:id, :title, :slug])
  |> Brando.Query.with_include(category: [select: [:id, :title]])

Brando.Repo.all(query)
```

Prefer the context API for normal application reads so filters, cache keys,
soft-deletion defaults, and return values stay consistent across callers.
