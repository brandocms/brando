# Datasources

A datasource supplies entries to a reusable content module. Use a **list** for an
automatically queried collection and a **selection** when editors choose and order
the entries. The Blueprint also supports a **single** callback for callers that
resolve one identifier; the standard module render adapters currently populate
entries for list and selection types.

This example adds related page cards to an existing application Blueprint. It
assumes working [modules and blocks](block_editor.md), persisted page identifiers,
and a running content-rendering queue.

## Declare automatic and selected pages

Inside the Blueprint:

```elixir
datasources do
  datasource :recent_pages do
    type :list
    list &__MODULE__.recent_pages/3
  end

  datasource :selected_pages do
    type :selection
    list &__MODULE__.page_choices/3
    get &__MODULE__.selected_pages/1
  end
end

def recent_pages(_module, language, _vars) do
  Brando.Pages.list_pages(%{
    filter: %{language: language, has_url: true},
    status: :published,
    order: [{:desc, :updated_at}, {:desc, :id}],
    limit: 6,
    preload: [:meta_image]
  })
end

def page_choices(_module, language, _vars) do
  Brando.Content.list_identifiers(Brando.Pages.Page, %{
    language: language,
    order: "asc title, asc entry_id"
  })
end

def selected_pages(identifiers) do
  with {:ok, entries} <- Brando.Content.get_entries_from_identifiers(
         identifiers, %{status: :published, preload: [:meta_image]}
       ) do
    {:ok, Enum.reject(entries, &is_nil/1)}
  end
end
```

The callbacks return `{:ok, results}`. A list returns entries directly; a
selection's `list` returns **identifiers for the picker**, and its `get` resolves
the selected identifiers into entries for rendering. The first list argument may
be the registered module string or module atom supplied by the caller; this
example deliberately uses the known Pages schema instead of querying that value
blindly.

`get_entries_from_identifiers/2` preserves the incoming identifier order, including
mixed schemas. Pass an options map, such as `%{preload: [...]}`; the older bare
preload-list argument is deprecated. Missing or filtered entries can occupy nil
positions in its result, so remove those before rendering. An empty selection
returns `{:ok, []}` without invoking your `get` callback.

Use explicit publication and language restrictions in your own queries. Picker
choices are not a substitute for publication checks when the module later renders.
If `get` queries the IDs itself, an SQL `IN` condition does not preserve the
editor's order; reconstruct it or use the helper above.

## Connect a module and render cards

In the module editor, enable its datasource, choose the Blueprint, then select
`recent_pages` or `selected_pages`. Insert the module into a page. For a selection,
choose two pages and drag them into the desired order.

A HEEx module template can render those entries:

```heex
<section :if={@entries != []} aria-label="Related pages">
  <ul>
    <li :for={page <- @entries}>
      <a href={Brando.Blueprint.URL.resolve(page)}>{page.title}</a>
    </li>
  </ul>
</section>
```

The equivalent Liquid template uses `entries`:

```liquid
{% if entries != empty %}
<ul>
  {% for page in entries %}
    <li>{{ page.title }}</li>
  {% endfor %}
</ul>
{% endif %}
```

Save, reload, and inspect the rendered page. Reorder the selection and verify the
public output follows it. Unpublish a selected page and confirm your renderer
omits it. Treat a callback error as a real rendering failure: the adapters expect
`{:ok, entries}`, so return `{:ok, []}` for a legitimate empty result and avoid
silently turning an unavailable external service into “no content.”

## Variables, selection metadata, and single results

The list callback's third argument is a map of the module block's variables,
keyed by strings. Current adapters map each var's `key` to its stored `value`;
do not assume every typed var has been converted into a rich asset or boolean
there. Normalize and validate user-editable values in the callback, and handle
missing keys so a new block can render before its options are complete.

Selection datasources may declare per-selection metadata:

```elixir
datasource :featured_pages do
  type :selection
  list &__MODULE__.page_choices/3
  get &__MODULE__.selected_pages/1
  meta :caption, :text, label: "Card caption"
end
```

That metadata belongs to the selected entry's placement. Render adapters expose
`entries_with_meta` alongside `entries`, as `%{entry: entry, meta: meta}` maps.
`meta` is nil when no placement metadata was stored. For the caption above, use
`get_in(item, [:meta, "caption"])` and render an empty/missing caption conditionally.

A single resolver takes one identifier, with an application-defined return value:

```elixir
datasource :one_page do
  type :single
  get fn identifier ->
    Brando.Pages.get_page(%{
      matches: %{id: identifier.entry_id},
      status: :published
    })
  end
end
```

Call it through `Brando.Datasource.get_single(YourBlueprint, "one_page", identifier)`.
It does not automatically populate a standard module's `@entries`; use list or
selection for that editor workflow. Function callbacks can also be MFA tuples;
runtime arguments come first, followed by the tuple's extra-argument list.

## Request-dependent content

Stored `rendered_blocks` has no current browser request. To render a datasource
from the route being visited, load the entry's block associations and use:

```elixir
entry = Brando.Repo.preload(entry, Brando.Blueprint.preloads_for(entry.__struct__))
```

```heex
<Brando.HTML.render_data conn={@conn} entry={@entry} />
```

The callback receives `vars["request"]`, whose `params` are **route path params**
and whose `url` is the request path. The old `"response"` example is incorrect;
query-string params are not automatically included. A callback can read:

```elixir
slug = get_in(vars, ["request", :params, "category_slug"])
```

Provide a sensible no-request behavior because the same callback may run during
stored rendering, previews, or background invalidation. If you cache dynamic
output yourself, include every relevant tenant, language, and route input in its
cache key. Never cache per-user content as a shared page render.

## Keep dependent pages fresh

Context mutations and sequencing invalidate datasources registered on the changed
schema and enqueue their consumers for rendering. A joined schema is not inferred
as a dependency. For example, if an Area datasource lists areas with grants, a
Grantee mutation must explicitly invalidate the Area datasource:

```elixir
mutation :update, Grantee do
  fn entry ->
    Brando.Datasource.update_datasource({Area, :list, :areas_with_grants}, entry)
  end
end
```

Add the same callback to create/delete when they change the result, or register
the datasource on the schema whose mutations actually drive it. The invalidation
helper returns `{:ok, entry}` for chaining. Direct repo/SQL imports bypass this
boundary; invalidate affected datasources once the import is complete.

Verify after the queue drains: edit a listed entry, change a joined dependency,
reorder selected entries, and inspect stored page output in both languages.
Invalidating a datasource queues work; it does not synchronously regenerate a
static deployment or an application-owned external cache.
