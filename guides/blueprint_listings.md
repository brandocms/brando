# Blueprint listings

A listing is the admin page that lists a content type's entries. Three pieces
make one:

1. the `listings` section of the Blueprint: which entries to load, how a row
   looks, and the filters, sorts, actions and exports around them;
2. a listing LiveView that renders the `Content.List` component for the
   schema;
3. the context's list function and its `filters` clauses, which run the
   query the listing builds.

This guide covers all three. Field declarations are in
[Attributes, relations, and assets](blueprint_fields.md), and the context's
query options are in [Querying](querying.md).

## A complete example

```elixir
defmodule MyApp.Articles.Article do
  use Brando.Blueprint,
    application: "MyApp",
    domain: "Articles",
    schema: "Article",
    singular: "article",
    plural: "articles"

  import Brando.Blueprint.Listings.Components.Core

  trait :creator
  trait :sequenced
  trait :status
  trait :timestamped

  identifier ~H"{@entry.title}"
  absolute_url ~H"/articles/{@entry.slug}"

  attributes do
    attribute :title, :string, required: true
    attribute :slug, :slug, required: true
    attribute :featured, :boolean, default: false
    attribute :section, :enum, values: [:news, :essays, :reviews], default: :news
  end

  listings do
    listing do
      query %{order: [{:asc, :sequence}, {:desc, :inserted_at}]}
      limit 50

      filter label: t("Title"), key: "title"
      filter label: t("Featured"), key: "featured", type: :boolean

      filter label: t("Section"), key: "section", type: :select do
        option t("All sections"), nil
        option t("News"), "news"
        option t("Essays"), "essays"
        option t("Reviews"), "reviews"
      end

      sort :manual, label: t("Manual order"), order: [{:asc, :sequence}, {:desc, :inserted_at}]
      sort :newest, label: t("Newest first"), order: [{:desc, :inserted_at}]
      sort :title, label: t("Title A–Z"), order: "asc title"

      action label: t("Feature"), event: "feature_article"
      selection_action label: t("Feature selected"), event: "feature_selected"

      export :titles do
        label t("Titles and URLs")
        fields [:id, :title, :slug, :status]
        query %{status: :published, order: [{:asc, :title}]}
      end

      component &__MODULE__.listing_row/1
    end
  end

  def listing_row(assigns) do
    ~H"""
    <.update_link entry={@entry} columns={9}>
      {@entry.title}
      <:outside>
        <small :if={@entry.featured} class="badge">{gettext("Featured")}</small>
      </:outside>
    </.update_link>
    <.url entry={@entry} />
    """
  end
end
```

The context gives every filter a clause:

```elixir
filters Article do
  fn
    {:title, title}, query ->
      from q in query, where: ilike(q.title, ^"%#{title}%")

    {:featured, "true"}, query ->
      from q in query, where: q.featured == true

    {:section, section}, query ->
      from q in query, where: q.section == ^section
  end
end
```

The LiveView renders the listing and handles the custom events:

```elixir
defmodule MyAppAdmin.Articles.ArticleListLive do
  use BrandoAdmin.LiveView.Listing, schema: MyApp.Articles.Article
  use Gettext, backend: MyAppAdmin.Gettext

  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Workspace

  def render(assigns) do
    ~H"""
    <div class="admin-workspace workspace-list content-workspace">
      <Workspace.header icon={@page_icon} title={gettext("Articles")}>
        <.link :if={@admin_create_url} navigate={@admin_create_url} class="workspace-button primary">
          {gettext("Create new")}
        </.link>
      </Workspace.header>

      <.live_component
        module={Content.List}
        id={"content_listing_#{@schema}_default"}
        schema={@schema}
        current_user={@current_user}
        uri={@uri}
        params={@params}
        listing={:default}
      />
    </div>
    """
  end

  def handle_event("feature_article", %{"id" => id}, socket) do
    MyApp.Articles.update_article(id, %{featured: true}, socket.assigns.current_user)
    BrandoAdmin.LiveView.Listing.update_list_entries(socket.assigns.schema)
    {:noreply, socket}
  end

  def handle_event("feature_selected", %{"ids" => ids}, socket) do
    for id <- Jason.decode!(ids) do
      MyApp.Articles.update_article(id, %{featured: true}, socket.assigns.current_user)
    end

    BrandoAdmin.LiveView.Listing.update_list_entries(socket.assigns.schema)
    {:noreply, socket}
  end
end
```

`mix brando.gen` writes the LiveView, routes and context for a new Blueprint;
see [Installation and generators](generators.md#generate-a-content-type).

## The listing LiveView

```elixir
use BrandoAdmin.LiveView.Listing, schema: MyApp.Articles.Article
```

`schema:` is required. A dashboard that lists nothing may pass `schema: nil`.
The optional `page_title:` takes a string or a zero-arity function and
becomes `@page_title`.

The LiveView gets these assigns: `@schema`, `@page_icon` (the Blueprint's
`content_icon`), `@page_title`, `@admin_create_url` (the create form's path,
or `nil` when the current user may not create entries), `@current_user`,
`@params` and `@uri`. It also gets Brando's handlers for the built-in row and
selection actions, the status menu, and the messages that refresh the listing
or show a toast. Events Brando does not handle reach your own
`handle_event/3`.

### Rendering `Content.List`

`Content.List`, aliased from `BrandoAdmin.Components`, is a LiveComponent.
Pass it:

* `id`: always `"content_listing_#{@schema}_default"`. Live updates, the
  delete and translation actions, and `send_update/2` from Brando's hooks
  address the listing by this id, even when it renders a listing other than
  `:default`. One schema can therefore have one listing component per page.
* `schema`, `current_user`, `uri` and `params`: from the LiveView's assigns.
* `listing`: the name of the listing to render. Default `:default`. It is
  read when the component mounts, so changing it later has no effect;
  navigate to another LiveView instead.

The rest are optional:

* `hidden_filters`: filter keys, as atoms, that should not show as active
  filter chips. Use it for keys that `query` sets which editors cannot
  change, such as `hidden_filters={[:parent_id]}`. Default `[]`.
* `extra_selection_actions`: more actions for the selection menu, as maps
  with `:label` and `:event`. They behave like
  [`selection_action`](#selection-actions) and are listed after the
  Blueprint's own. Default `[]`.
* `empty_title` and `empty_description`: shown when no entries match.
  Without `empty_title`, the listing says "No matching entries found".
* a `:column_header` slot, rendered between the tools bar and the rows, for
  column headings.

```heex
<.live_component
  module={Content.List}
  id={"content_listing_#{@schema}_default"}
  schema={@schema}
  current_user={@current_user}
  uri={@uri}
  params={@params}
  hidden_filters={[:parent_id]}
  extra_selection_actions={[%{label: gettext("Move to folder"), event: "move_selected"}]}
  empty_title={gettext("No articles yet")}
  empty_description={gettext("Create the first one with the button above.")}
>
  <:column_header>
    <div class="col-9">{gettext("Title")}</div>
  </:column_header>
</.live_component>
```

### Menu items

`menu_item MyApp.Articles.Article` in the admin menu links to
`/admin/<domain>/<plural>` and needs a listing named `:default`; without one
the menu module raises when it compiles. The default listing's `query`, minus
`preload`, is encoded into the link's query string so the first page matches.
The listing reads `order`, `status`, `limit` and `page` back from the URL;
other keys, such as `filter` or `language`, are not accepted there and make
the listing raise. Keep the default listing's `query` to `order`, `status` and
`preload` when the schema has a menu item, and set fixed filters with
`hidden_filters` and a context clause instead.

## Declaring listings

```elixir
listings do
  listing do
    # the :default listing
  end

  listing :drafts do
    # a second, named listing
  end
end
```

`listing` takes an optional name, written positionally. It defaults to
`:default`. A Blueprint can declare several listings; a LiveView chooses one
with the `listing` attribute of `Content.List`, and child listings name the
one their rows use. Declaring the same name twice prints a compile warning
and leaves both in place, so keep names unique.

A listing accepts these options:

* `component`: a one-arity function component that renders a row. See
  [Rows](#rows).
* `query`: a map merged into the list query. Default `%{}`. See
  [The listing query](#the-listing-query).
* `limit`: entries per page. Default 25. `0` shows every entry on one page.
  It must be zero or a positive integer.
* `sortable`: whether rows can be dragged into a new order. Default `true`.
  It only has an effect with `trait :sequenced`.
* `default_actions`: whether rows get Brando's built-in actions (edit,
  delete, duplicate and the translation actions). Default `true`.
* `decorate`: a function that receives the loaded page of entries (and,
  with two arguments, the signed-in user) and returns it. See
  [Decorating entries](#decorating-entries).

It also contains `filter`, `sort`, `action`, `selection_action`, `export` and
`child_listing` declarations, described below.

## Rows

`component` names the function component that renders each row. It receives
`@entry` and `@current_user`, the signed-in user:

```elixir
listing do
  component &__MODULE__.listing_row/1
end

def listing_row(assigns) do
  ~H"""
  <.update_link entry={@entry} columns={9}>{@entry.title}</.update_link>
  <.url entry={@entry} />
  """
end
```

A listing without `component` shows only Brando's own columns: status,
drag handle, editor and the action menu. Every real listing needs one.

Rows are laid out on a column grid. Brando's own columns come before and
after your component: the status dot and drag handle at the start, then
alternates, translation status, the creator column (with `trait :creator`)
and the action menu at the end. Size your cells with `columns`.

### Row components

Import the components the row uses. `Core` covers most rows; import `Cover`
and `Children` only when the row shows a cover image or a child-listing
button:

```elixir
import Brando.Blueprint.Listings.Components.Core
import Brando.Blueprint.Listings.Components.Cover, only: [cover: 1]
import Brando.Blueprint.Listings.Components.Children, only: [children_button: 1]
```

`Brando.Blueprint.Listings.Components` still exposes all of them for older
Blueprints. Importing the smaller modules keeps a Blueprint from compiling
against the cover and child-listing admin code it does not use.

`Core.update_link/1` links to the entry's edit form:

* `entry` (required) and `columns` (required, the width in grid columns);
* `offset`: columns to skip before the cell;
* `class`: extra classes;
* `skip_style`: drops the default `entry-link` styling. Default `false`;
* slots: the inner block is the link text, `:before` renders before the
  link inside the cell, and `:outside` renders after the link, outside it.

`Core.url/1` renders a link icon to the entry's public URL
([`absolute_url`](blueprints.md#absolute-url)). It takes `entry`, plus
optional `class` and `offset`, and always takes one column. It only shows
the icon while `entry.status` is `:published`, so it needs `trait :status`.

`Core.field/1` is a plain cell: `columns` (required), `offset`, `class` and
an inner block.

`Core.i18n/1` renders the request language's text from a language map, such
as an `:i18n_string` attribute: `<.i18n map={@entry.subtitle} />`.

`Cover.cover/1` renders an image thumbnail:

* `image` (required; `nil` shows a placeholder) and `columns` (required);
* `size`: the image size to show. Default `:thumb`;
* `padded`, `circular` and `top`: presentation flags. Default `false`;
* `offset` and `class`.

The listing preloads every image asset of the schema, so
`<.cover image={@entry.cover} columns={2} />` needs no `query` preload.

`Children.children_button/1` toggles [child rows](#child-listings). It takes
`entry` and `fields` (required), plus `columns` (default 1), `offset` and
`class`.

## The listing query

The listing builds one options map and passes it to the context's
`list_<plural>/1`. In order:

1. `%{paginate: true, limit: limit}`;
2. the listing's `query`, merged over that, so `query` may set its own
   `limit`;
3. the [filter defaults](#defaults), for keys `query.filter` does not set;
4. with `trait :translatable`, `language:` set to the editor's current
   content language. This replaces any `language` in `query`;
5. preloads Brando's columns need: `creator` and `updated_by` with
   `trait :creator`, `alternate_entries` for translatable schemas with
   alternates, and every image asset;
6. the order: the first [sort](#sorts) when the listing declares sorts,
   otherwise `query.order`, otherwise `[{:asc, :sequence}, {:desc,
   :inserted_at}]` for sequenced schemas;
7. what the URL holds: the page, page size, chosen sort, status and filter
   values.

Use `query` for fixed preloads, ordering and status, and for filters that
should always apply:

```elixir
listing do
  query %{
    status: :published,
    preload: [:category],
    filter: %{archived: false}
  }
end
```

The options are those of [Querying](querying.md#query-options), with a few
limits from how the listing uses them:

* `filter` must be a map. Every key in it, and every listing filter, needs a
  clause in the context's `filters`.
* `preload` may be a list or a zero-arity function capture returning one;
  the function runs on every load. It can use the map form described in
  [Querying](querying.md).
* `paginate` must stay `true`. Don't use `cache`, which returns a plain list
  the listing cannot page.
* With `status` set, editors cannot clear the status filter; deselecting it
  returns to the query's status.

A row component sees one entry at a time, so data the query cannot preload
must come from [`decorate`](#decorating-entries).

## Decorating entries

`decorate` takes a one-arity function. It receives the loaded page of entries
as a list and returns the list, typically with a key put on each entry. It
runs once per page load, so a lookup can be batched instead of made once per
row:

```elixir
listing do
  decorate &__MODULE__.put_usage/1
  component &__MODULE__.listing_row/1
end

@doc false
def put_usage(entries), do: Brando.Content.Usage.put(entries, :image)
```

Rows then read `@entry.usage`. Prefer a local capture, as above: the listing
keeps the function at compile time, and a remote capture makes the Blueprint
compile against the module it calls.

When the extra data depends on who is looking (a reviewer sees only their own
scores, say), give `decorate` a two-arity function; it also receives the
signed-in user:

```elixir
listing do
  decorate &__MODULE__.put_scores/2
  component &__MODULE__.listing_row/1
end

@doc false
def put_scores(entries, user), do: MyApp.Reviewing.put_visible_scores(entries, user)
```

`decorate` runs for the listing's own rows. Child rows and exports do not go
through it.

## Filters

```elixir
filter label: t("Title"), key: "title"
filter label: t("Featured"), key: "featured", type: :boolean
filter label: t("Section"), key: "section", type: :select, options: &__MODULE__.section_options/1
```

Every filter has:

* `label` (required): shown in the admin, translated through the
  Blueprint's Gettext domain.
* `key` (required): a snake_case string. It names the URL parameter
  (`filter:title`) and, as an atom, the key the context's `filters` clause
  receives (`{:title, value}`).
* `type`: `:text` (the default), `:boolean` or `:select`.
* `default`: the value the filter starts with. See [Defaults](#defaults).

Filter keys must be unique in a listing, together with sort, export and
child-listing names. A filter can also be written as a block:

```elixir
filter do
  label t("Section")
  key "section"
  type :select
  option t("All sections"), nil
  option t("News"), "news"
end
```

### What the context receives

The listing passes the values as `filter: %{key: value}` to
`list_<plural>/1`, and the context runs each pair through its `filters`
clauses ([Querying](querying.md#filtering-and-matching)). A missing clause
raises `Brando.Exception.QueryFilterClauseError`. Values from the URL are
always strings:

* a `:text` filter sends what the editor typed;
* a `:boolean` filter sends `"true"`, or `"false"` with `off: false`;
* a `:select` filter sends the chosen option's value.

Before the query runs, text filter values are escaped for `LIKE`: `%`, `_`
and `\` get a backslash, so they can go straight into an `ilike` pattern, as
in the example at the top. Select and boolean values are ones the listing
declared and reach the context as they are: `"in_progress"` stays
`"in_progress"`.

### Filters that depend on the user

A filter's meaning may depend on the signed-in user ("hide what I have
reviewed"). The listing passes the user to the context, and a `filters`
function whose clauses take a third argument receives it as
`%{current_user: user}` (see `Brando.Query.filters/2`). Every clause of that
function then takes the third argument:

```elixir
# The Blueprint
filter label: t("Hide what I have reviewed"), key: "hide_reviewed", type: :boolean

# The context
filters Application do
  fn
    {:hide_reviewed, "true"}, query, %{current_user: user} ->
      from(a in query, where: a.id not in subquery(reviewed_by(user)))

    {:hide_reviewed, _}, query, _ ->
      query
  end
end
```

Called outside a listing, the user is whatever `current_user:` the `list_*`
call passes, or `nil`.

### Text filters

Text filters are the listing's search field. The tools bar shows one at a
time with a button that cycles through them; the key **f** focuses the
field. Typing filters the listing after a short pause. There is no separate
search box: declare a text filter for each field editors search by, or one
key such as `"search"` whose clause searches several columns.

### Boolean filters

A `:boolean` filter is a toggle. Switched on, the context receives `"true"`.
Switched off, the filter no longer applies and every entry shows.

`off: false` makes "off" mean "only entries without the value": the context
receives `"false"` when the toggle is off, and the filter starts there. Only
boolean filters accept `off:`.

```elixir
# Off: every entry
filter label: t("Not in use"), key: "unused", type: :boolean

# Off: only entries that are not featured
filter label: t("Featured"), key: "featured", type: :boolean, off: false
```

The second filter needs both clauses:

```elixir
{:featured, "true"}, query -> from q in query, where: q.featured == true
{:featured, "false"}, query -> from q in query, where: q.featured == false
```

### Select filters

A `:select` filter shows a dropdown. Give it static options with `option
label, value`:

```elixir
filter label: t("Section"), key: "section", type: :select do
  option t("All sections"), nil
  option t("News"), "news"
  option t("Essays"), "essays"
end
```

or an `options` function. It receives `%{language: language}`, the editor's
content language, and returns `{label, value}` tuples. It runs whenever the
tools bar renders, so keep it cheap:

```elixir
filter label: t("Category"), key: "category_id", type: :select,
  options: &__MODULE__.category_options/1

def category_options(%{language: language}) do
  categories = MyApp.Articles.list_categories!(%{language: language, order: "asc name"})
  [{gettext("All categories"), nil} | Enum.map(categories, &{&1.name, to_string(&1.id)})]
end
```

Option values are strings or `nil`. Static option values must be unique and
labels non-empty, and a select filter needs either static options or the
function.

Include an option with the value `nil` and put it first. Choosing it clears
the filter. Without it, the browser shows the first option as selected while
no filter applies.

### Defaults

`default` sets the value a filter starts with. The listing merges it into
`query.filter` for the first load, and a value in `query.filter` for the same
key takes precedence. The value must suit the type: a string for `:text` and
`:select` (one of the static values, when the options are static), or a
boolean for `:boolean`.

* `default: true` starts a boolean filter switched on. Switching it off then
  sends nothing, unless `off: false`, which sends `"false"`.
* `default: false` on a boolean filter is the same as no default.
* A text or select filter with a default always applies: choosing the `nil`
  option or clearing the field returns to the default. Leave `default` out
  if editors need to see every entry.

A filter that differs from where it started shows as a chip above the rows,
and **Reset filters** returns boolean and select filters to their defaults.
Keys from `query.filter` that are not declared filters show as chips too;
list them in `hidden_filters` to hide them.

## Sorts

```elixir
sort :manual, label: t("Manual order"), order: [{:asc, :sequence}, {:desc, :inserted_at}]
sort :newest, label: t("Newest first"), order: [{:desc, :inserted_at}]
sort :title, label: t("Title A–Z"), order: "asc title"
```

A sort takes an atom key, a `label` and an `order`. The order is a list of
`{direction, field}` tuples or the string form, a comma-separated list such
as `"asc title, desc inserted_at"`. Directions are `asc` and `desc`, and
their `_nulls_first` and `_nulls_last` variants. A field may be one
association step away: `{:asc, {:category, :name}}` or `"asc category.name"`.

For an order columns cannot express, `order` may be a function that takes the
list query and returns it ordered. The listing keeps such a sort in the URL by
its key (`?sort=score`), so the menu limits below do not apply to it. The
function should keep one row per entry (join a grouped subquery rather than
grouping the query itself), so pagination still counts entries:

```elixir
sort :score, label: t("Highest score"), order: &__MODULE__.order_by_score/1

@doc false
def order_by_score(query) do
  scores = from(r in Review, group_by: r.application_id, select: %{id: r.application_id, total: sum(r.score)})

  from(a in query,
    left_join: s in subquery(scores),
    on: s.id == a.id,
    order_by: [desc_nulls_last: s.total, asc: a.id]
  )
end
```

When a listing declares sorts, they appear in a menu in the tools bar, and
the **first sort is the listing's initial order**: it replaces `query.order`.
Put the order the listing should open with first.

With `trait :sequenced` and `sortable true`, rows can be dragged while the
active sort orders by `:sequence`; the menu marks those sorts with "Rows can
be dragged in this order". Without sorts, drag handles show whatever
`query.order` is, so declare a sequence sort first when the listing also
offers others.

Limits of the sort menu:

* A sort through an association works as the first sort, but choosing it
  from the menu fails. Keep association sorts first, or order by a column on
  the schema itself.
* The chosen sort is kept in the URL grouped by direction. A sort with two
  fields in the same direction, such as `[{:asc, :category_id}, {:asc,
  :title}]`, loses one of them when picked from the menu, and the menu may
  then show the first sort as active. Such orders also work as the first
  sort.

## Pagination

Listings are always paginated. `limit` sets the page size (default 25; `0`
for everything on one page). Below the rows, editors can switch between 25,
50 and all entries per page, whatever `limit` says, and move between pages.
The page and page size are kept in the URL.

## Row actions

Each row has an action menu. With `default_actions true`, Brando adds these,
each shown only when its condition holds:

* **Edit**: when the user may update the entry.
* **Delete**: when the user may delete it. A dialog describes what goes with
  the entry before it is deleted.
* **Duplicate**: when the context has `duplicate_<singular>/2` and the user
  may duplicate the entry and create entries.
* **Duplicate to [language]**: for translatable schemas in independent mode
  with more than one language, one item per language. **Translate to
  [language]** is added when [AI](blueprint_forms.md#ai-generated-values) is
  configured.
* **Create translation [language]**: for synchronized translatable schemas.
* **Re-render**: for `trait :blocks`, shown to superusers who may publish.
* **Undelete**: for soft-deleted entries the user may restore. This one is
  shown even with `default_actions false`.

`default_actions false` removes the rest, leaving only your own actions.

### Custom actions

```elixir
action label: t("Feature"), event: "feature_article"
action label: t("Archive"), event: "archive_article", confirm: t("Archive this article?")
action label: t("Preview"), event: JS.push("preview_article") |> JS.add_class("loading")
```

`action` takes:

* `label` (required): the menu text, translated through the Blueprint's
  Gettext domain;
* `event` (required): a non-empty event name or a `Phoenix.LiveView.JS`
  command;
* `confirm`: `false` (the default), or a message shown in a confirmation
  dialog before the event is sent. `confirm: true` is rejected; write the
  question instead.

Custom actions are shown on every row, after the built-in ones, without a
permission check; check permissions in the handler.

An event name is pushed to the listing LiveView with the entry's `"id"` (an
integer) and `"language"`:

```elixir
def handle_event("feature_article", %{"id" => id}, socket) do
  # ...
  {:noreply, socket}
end
```

A `JS` command runs as written; a `JS.push/2` in it receives `"id"` and
`"language"` as strings. Using the name of a built-in event, such as
`"edit_entry"`, `"duplicate_entry"` or `"delete_entry"`, runs Brando's
handler. That is how a listing with `default_actions false` puts some of them
back under its own labels.

## Selection actions

Shift-click selects a row; Shift with Cmd or Ctrl selects a range. While rows
are selected, a bar offers **Clear selection** and an **Actions** menu.

```elixir
selection_action label: t("Feature selected"), event: "feature_selected"

selection_action label: t("Reject selected"),
                 event: "reject_selected",
                 confirm: t("Reject the selected applications?"),
                 visible: &__MODULE__.superuser?/1
```

`selection_action` takes:

* `label` and `event` (a name or a `JS` command), both required;
* `confirm`: `false` (the default), or a question shown in a confirmation
  dialog before the event is sent;
* `visible`: a function of the signed-in user that decides whether to offer
  the action. It only hides the menu item: the LiveView handling the event
  must still check the user itself.

The event goes to the listing LiveView with `"ids"`, a JSON-encoded list of the selected
IDs, so decode it with `Jason.decode!/1`. The Blueprint's selection actions
come after Brando's own: **Delete selected** (when the user may delete
entries) and, for translatable schemas with `duplicate_<singular>/2`,
**Duplicate selected to [language]**.

The selection stays after the action runs. To clear it from the LiveView:

```elixir
send_update(BrandoAdmin.Components.Content.List,
  id: "content_listing_#{socket.assigns.schema}_default",
  action: :clear_selection
)
```

`extra_selection_actions` on the component adds actions that are not in the
Blueprint, for example ones that depend on the LiveView's state.

## Exports

```elixir
export :titles do
  label t("Titles and URLs")
  fields [:id, :title, :slug, :status]
  query %{status: :published, order: [{:asc, :title}]}
end
```

`export` takes an atom name and:

* `label` (required): the menu text;
* `fields` (required): the entry fields to write, as a non-empty list without
  duplicates. Each becomes a column, headed by the field name;
* `query`: the options for `list_<plural>/1`. Default `%{}`, which exports
  every entry the context returns. Leave out `paginate`: the export needs a
  plain list;
* `type`: `:csv`, the only supported type and the default;
* `description`: accepted, but not shown anywhere.

The keyword form, `export :titles, label: ..., fields: [...]`, is
equivalent.

With at least one export, the tools bar shows an **Export** menu to users
with the `:export` permission. The export runs its own `query`: it does not
use the listing's filters, status, language or sort. Each value is written
with `to_string/1`, so export plain fields; associations, maps and
`:i18n_string` fields fail. The file is named
`<plural>_export_<timestamp>.csv` and its columns are separated by tabs.

## Child listings

A row can expand to show related entries below it, such as a page's
subpages. The row renders a button with `children_button`, and the listing
says which listing renders each child:

```elixir
listings do
  listing do
    query %{
      filter: %{parent_id: nil},
      preload: [children: %{module: __MODULE__, order: [asc: :sequence], hide_deleted: true}]
    }

    child_listing name: :subpages, schema: __MODULE__
    component &__MODULE__.listing_row/1
  end

  listing :subpages do
    default_actions false
    action label: t("Edit subpage"), event: "edit_entry"
    action label: t("Delete subpage"), event: "delete_entry", confirm: t("Delete this subpage?")
    component &__MODULE__.subpage_row/1
  end
end

def listing_row(assigns) do
  ~H"""
  <.update_link entry={@entry} columns={8}>{@entry.title}</.update_link>
  <.children_button entry={@entry} fields={[:children]} />
  """
end
```

`child_listing` takes `name:` and `schema:`, both required. `name` must be a
listing declared in the same Blueprint, the parent's. `schema` is the
module of the child entries. A listing can have one child listing per
schema.

`children_button` counts the entries in each of `fields` and is hidden when
there are none. The fields are associations of the entry and must be
preloaded, typically through `query.preload`; an unloaded association makes
the row fail. Clicking it shows the children below the row, each rendered by
the `component` of the listing that its `child_listing` names.

From the child's listing, only `component`, `action`, `default_actions` and
`sortable` are used. Filters, sorts, exports and the rest belong to the
parent listing. With `sortable true` and `trait :sequenced` on the child
schema, child rows can be dragged within their parent.

The built-in row actions of a child row act on the parent listing's schema.
For children of the same schema, as above, that is correct. For children of
another schema, such as a page's fragments, set `default_actions false` and
handle custom events in the LiveView, as Brando's page listing does.

## Status, trash, and other traits

Several traits change the listing without any listing declaration:

* `trait :status`: status buttons in the tools bar (published, deactivated,
  draft, pending) and a status dot on each row whose menu changes the status
  when the user may publish.
* `trait :soft_delete`: deleted entries are left out. With `trait :status`
  too, a **Deleted** status button shows the trash, deleted rows name who
  deleted them, and each has **Undelete**. Without `trait :status` the trash
  cannot be reached from the listing.
* `trait :sequenced`: drag ordering, and the default order without sorts.
  Dragging also needs the `:reorder` permission.
* `trait :translatable`: the listing shows the editor's content language,
  rows link their translations, and the duplicate and translate actions
  appear.
* `trait :creator`: a column with the creator and last editor.
* `trait :scheduled_publishing`: pending entries with a publish time show a
  clock instead of a status dot.
* `trait :blocks`: the **Re-render** action.

See [Traits](blueprint_traits.md) for what each trait adds to the schema.

## Live updates

The listing reloads its entries when the schema's listing topic receives an
update. Brando's own actions, scheduled publishing and translation sync send
one. Code that changes entries while a listing is open, such as a custom
action's handler or a background job, calls:

```elixir
BrandoAdmin.LiveView.Listing.update_list_entries(MyApp.Articles.Article)
```

Every listing of that schema open in the same site and environment reloads
its current page, keeping filters, sort and selection.

## Compile-time checks

Listing declarations are checked when the Blueprint compiles, and a mistake
fails the compilation with the listing and entry it is about:

* listing names are atoms, and `limit` is zero or a positive integer;
* `query.filter`, when present, is a map;
* filter keys, sort keys, export names, and child-listing names and schemas
  are unique within the listing;
* filter labels are non-empty, keys are snake_case strings, `off:` is only
  on boolean filters, `options` only on select filters, and defaults match
  the filter type and static options;
* sort labels are non-empty and orders are valid;
* action labels are non-empty, events are non-empty strings or `JS`
  commands, and `confirm` is `false` or a message;
* export labels are non-empty, `type` is `:csv`, and `fields` is a non-empty
  list without duplicates;
* child listings name a listing declared in the Blueprint and a module.

The checks do not cover `query` keys other than `filter`, that a listing has
a `component`, that the context has clauses for the filter keys, or the
`default` of a select filter whose options come from a function.
