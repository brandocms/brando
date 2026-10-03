# Frontend edit mode

Frontend edit mode lets a signed-in admin edit blocks where they appear: on the
published site. Clicking a block opens it in a sidebar with the same block editor
the admin uses. The page shows each change as it is typed, and saving stores the
block through its entry, as a save in the admin does.

## Switch it on

Frontend edit is off until it is switched on in config:

```elixir
config :brando, Brando.FrontendEdit, enabled: true
```

and the router's browser pipeline runs `Brando.Plug.FrontendEdit` after the
session is fetched and the tenant is resolved:

```elixir
pipeline :browser do
  plug :accepts, ["html"]
  plug :fetch_session
  # …
  plug Brando.Plug.Tenant
  plug Brando.Plug.Identity
  plug Brando.Plug.Navigation, key: "main", as: :navigation
  plug Brando.Plug.Fragment, parent_key: "partials", as: :partials
  plug Brando.Plug.FrontendEdit
end
```

New projects get the plug from `mix brando.install`; the config line is there,
commented out.

Visitors are not affected. The plug only acts for someone signed in to the admin
with backend access, and with the config off it does nothing at all.

## What an admin sees

An admin gets an **Edit page** button in the corner of every HTML page. It
switches edit mode on for their browser (a `_brando_frontend_edit` cookie), and
**Done** in the edit-mode toolbar switches it off.

In edit mode:

- Pointing at a block outlines it and names it. A click opens it in the sidebar,
  instead of following links in it. Hold **Alt** (Option) to use the page as
  usual.
- A click selects the nearest module. A block in a container opens the module
  it is in; an entry of a multi module opens the multi module; a block in a
  module's region or footnotes opens the module that owns them.
- The sidebar shows that block alone, without the entry's other fields or blocks.
  Adding blocks beside it, moving, duplicating and deleting it are left to the
  full editor; inside the block everything works as there, including images,
  videos and child blocks.
- The page updates as the block changes. **Save** (or ⌘S) saves the entry. Its
  stored HTML is rendered again, and pages that depend on it are queued for
  rendering, as with any save.
- The arrow in the sidebar's header opens the block in the full editor, which
  scrolls to it.
- Leaving a block with unsaved changes asks whether to save or discard them.
  Discarding reloads the page to show what is saved.

The sidebar also says:

- who else has the entry open, in the admin or on the website. The admin form
  shows a website editor among its presences with a small globe;
- when someone else saved the entry after the sidebar opened it. It will not
  save over their changes; **Reload** opens the block again with them;
- that a block belongs to a shared fragment, and how many pages embed it;
- when a revision of the entry is scheduled to be published, which will
  replace changes made now.

A synchronized translation's structure and media follow its source, as in the
admin: only its text can be edited.

## Entry fields

An entry's own fields — a title, an introduction, a cover image — are printed by
the site's templates, and also in places a marker would break, like `<title>`,
an `alt` attribute or JSON-LD. So the template marks the place where a field
shows, with the same helper everywhere:

```heex
<%!-- Site templates and HEEx modules --%>
<h1><.editable_field entry={@page} field={:title} /></h1>

<.editable entry={@project} field={:cover}>
  <.picture src={@project.cover} opts={[…]} />
</.editable>
```

```liquid
{%- comment -%} Liquid modules {%- endcomment -%}
<h2>{% editable_field entry.title %}</h2>
{% editable entry.cover %}{% picture entry.cover %}{% endeditable %}
```

- `editable_field` prints the value: rich-text fields as their HTML, anything
  else escaped. Use it where the value shows as text, not inside an attribute.
  In edit mode the page shows changes to it as they are typed, wherever it is
  printed, and blocks that read the field render again.
- `editable` wraps other markup showing the field, such as a picture or a list
  of related entries. The page shows the change once it is saved.
- `<Brando.HTML.render_rich_text entry={…} field={…} />` marks its field by
  itself.

Outside edit mode these print exactly what they wrap and nothing else, so they
can be added to existing templates without changing the published page.

A click on a marked field opens the field's input, as the entry's admin form
renders it, alone in the sidebar; saving writes only that field. A field can
be clicked when it is an input on the entry's default admin form and the admin
may update the entry. Inside a block, a marked field is the smaller target:
clicking the text opens the field, and the rest of the block opens the block.
"Open in the full editor" opens the form on the field's tab, at the field.

## Listings

A listing of chosen entries, like "Featured projects", is a datasource block
with a selection. Clicking it opens the block, with its selection: choose,
remove or reorder entries, and the page lists the new selection as it
changes. A listing generated by a query has nothing to choose. A listing a
controller builds itself is not editable, unless the entries it lists are a
field of the entry, marked with `editable`.

## How a page becomes editable

Pages normally print the HTML stored for each block field when the entry was
saved (`rendered_<field>`). In edit mode, Brando renders the fields again with
markers around each block, and the plug reads them to tell the browser what
can be edited. Every common way of printing blocks is covered:

- `{@page}`, `{@fragment}` and other entries' `Phoenix.HTML.Safe` output;
- `<Brando.HTML.render_blocks entry={@entry} />` and
  `<Brando.HTML.fragment … />`;
- `Brando.Pages.render_fragment/1,2,3` and `fetch_fragment/2`;
- `@entry.rendered_blocks` printed directly, for entries fetched with a
  generated context's single-entry query (`get_page/1`, `get_project/1`, …).

Fragments embedded in a block carry their own markers, so a click inside one
edits the fragment.

Edit-mode responses are sent with `cache-control: private, no-store`, and the
annotated HTML never reaches Brando's query cache, so nothing cached for
visitors carries markers.

### What is not covered

- Entry fields the templates do not mark (see [Entry fields](#entry-fields)),
  template markup and globals.
- Blocks printed from an entry fetched with a list query.
- Pages rendered by a connected LiveView: the markers are added in the request
  that renders the page.
- A statically built site (`Brando.SSG`) is edited on the running application,
  and published by building it again.

## Site scripts

The page is patched in place. A site whose scripts set up elements once (a
slider, a lightbox) can listen for the same event the live preview sends:

```js
document.addEventListener('brando:livepreview:patched', ({ detail }) => {
  detail.elements.forEach(el => initWidgets(el))
})
```

`detail.source` is `frontend-edit` for these changes, and `detail.type` is
`block` or `field` (a block field, or entry fields refreshed after a save). Mark elements a script takes over with
`data-lp-preserve`, as for the live preview.

## Content security policy

The overlay is an inline script and stylesheet, and the sidebar is an iframe of
the admin on the same origin. A content security policy must allow
`'unsafe-inline'` scripts for signed-in admins and `frame-src 'self'`, which
Brando's default headers do. The admin must be served from the site's own
origin.
