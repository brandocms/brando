# Live preview

Live preview renders the current unsaved entry through your application's own
Phoenix templates and layout. Editors can inspect a page at desktop, tablet, or
mobile dimensions, open the preview in another window, and create an expiring
shared snapshot when they have export access.

<!-- usage-rules:start topic="live-preview" -->

## Configure a view

Create `MyAppWeb.LivePreview` in the application's web namespace:

```elixir
defmodule MyAppWeb.LivePreview do
  use Brando.LivePreview

  preview_target Brando.Pages.Page do
    label "Page"
    description "Full page with its layout and content"
    layout {MyAppWeb.Layouts, "app"}
    template fn page -> {MyAppWeb.PageHTML, page.template} end
    template_prop :page
  end
end
```

Use the same layout/template assigns as your controller. `template_prop` is the
assign containing the edited entry (`:entry` by default). A single configured
view opens immediately from the editor's eye button.

<!-- usage-rules:end -->

## Offer more than one view

Declare another `preview_target` for the same schema and give it a unique `name`:

```elixir
preview_target MyApp.Articles.Article do
  name :detail
  label "Article"
  description "Full article with its page layout"
  layout {MyAppWeb.Layouts, "app"}
  template {MyAppWeb.ArticleHTML, "show"}
  template_prop :article
end

preview_target MyApp.Articles.Article do
  name :listing
  label "Article listing"
  description "The edited article alongside published stories"
  layout {MyAppWeb.Layouts, "app"}
  template {MyAppWeb.ArticleHTML, "index"}
  template_prop :article

  reassign_on_change [{:articles, [:title]}, {:articles, [:slug]}]

  assign :articles, fn entry, language ->
    articles = MyApp.Articles.list_articles!(%{
      filter: %{language: language},
      status: :published,
      order: "desc publish_at",
      limit: 6
    })

    if Enum.any?(articles, &(&1.id == entry.id)) do
      Enum.map(articles, fn article ->
        if article.id == entry.id, do: entry, else: article
      end)
    else
      [entry | articles] |> Enum.take(6)
    end
  end
end
```

Adapt the context, fields, ordering, and filtering to the application. The
callback replaces the persisted card with the unsaved entry when it is in the
query result; otherwise it places the edited entry first. This deliberately
includes new or draft articles so the editor can see their card. Decide whether
that behavior, a fixed position, or strict production filtering fits your site.
Brando does not infer a collection query from a detail template.

With multiple targets, the eye button opens **Preview as**, showing each label
and optional description. Selecting another view keeps the unsaved form and
block content, and reloads the preview with its new layout and template. The
current view is marked in the chooser; **Close preview** closes the pane. Tab and
Enter operate the choices; Escape and clicking outside dismiss the chooser.
Viewport buttons still control dimensions independently of the selected view.

Names are atoms unique within each schema. An unnamed target uses `:default`.
The default is `:default` when present, otherwise the first declared target.
Labels default to "Preview" for the unnamed target or a humanized target name;
provide explicit labels/descriptions for useful editor-facing choices.

<!-- usage-rules:start topic="live-preview" -->

## Preloads, assigns, and refresh behavior

- `schema_preloads` is passed to `Repo.preload/2` before assign callbacks. Include
  every association a callback or template uses, including nested preloads.
- `assign :key, fn entry -> ... end` and `fn entry, language -> ... end` compute
  additional template assigns. Language comes from the entry or site default.
- Assigns are cached separately from rendered HTML. Use `reassign_on_change`
  with `{assign_key, field_path}` pairs for every edited field the callback
  depends on. Switching targets recomputes assigns, even when both views use
  the same assign name.
- `mutate_data fn entry -> ... end` runs after assign callbacks and before block
  rendering. It changes preview data only; it cannot prepare input for an
  earlier callback or persist changes.
- `rerender_on_change [[:field]]` renders the whole `<body>` again when the
  field changes; see [Fields the layout shows](#fields-the-layout-shows).
- `template_section` and `template_css_classes` accept a string or an entry
  callback for layout context.

Templates receive `@LIVE_PREVIEW` and a preview connection. Reuse production
markup where possible. Collection callbacks receive preloaded, unsaved data
before block HTML is rendered; cards should use their normal metadata rather
than assuming freshly rendered block HTML is already present in the callback.

## Fields the layout shows

Every change to the entry updates the preview without any declaration: the
template renders again and the preview patches `<main>` in place. A field the
template shows, an image included, needs nothing in the target.

The layout around `<main>` renders again only on a full render. When the
layout shows an entry field, declare it with `rerender_on_change`, so a change
to it renders the `<body>` again:

```elixir
preview_target MyApp.Articles.Article do
  layout {MyAppWeb.Layouts, "app"}
  template {MyAppWeb.ArticleHTML, "show"}
  template_prop :article

  # The layout's header shows the article's cover as a hero image.
  rerender_on_change [[:cover]]
end
```

`<html lang>` and `<head>`, the page title and meta tags included, change only
when the preview reloads, so a field shown there needs no declaration either.

An assign is cached, so a field its callback reads goes in
`reassign_on_change`, wherever the assign is shown. When the layout shows the
assign, such as navigation in the entry's language, the field goes in both
lists:

```elixir
reassign_on_change [{:navigation, [:language]}]
rerender_on_change [[:language]]
```

A path names an entry field and covers everything below it:

- `[:items]`: a subform, with its rows added, removed or reordered and the
  fields inside them.
- `[:seo, :title]`: one field inside `:seo`. It also fires when all of `:seo`
  changes at once, as when another editor changes it.
- `[:cover]`: an image, video or file field, when one is picked, uploaded,
  edited in its drawer or removed.
- `[:category]`: a select that sets a relation with `update_relation`. For a
  select without it, declare its key, `[:category_id]`.

Both lists apply to every change to the field: typed, an accepted AI
suggestion, or another editor's.

## Elements the site's script takes over

The preview patches the page in place as the editor types. An element your
frontend script has taken over (a canvas it draws on, a widget it mounted
into) carries attributes and children the server's HTML knows nothing about,
and a patch would strip them. Mark such an element with `data-lp-preserve`,
set to what it shows:

```liquid
<canvas data-animation="{{ src }}" data-lp-preserve="{{ src }}"></canvas>
```

While the value is unchanged, the element and everything in it are left as
the script made them. When it changes, the element is patched like any other,
and the script has to follow the new value. Video players are preserved the
same way without the attribute.

Your script initialised the page once, when it loaded. Elements the preview
patches or inserts afterwards are not initialised again unless the script
listens for `brando:livepreview:patched`, dispatched on `document` after
every update:

```js
document.addEventListener('brando:livepreview:patched', ({ detail }) => {
  // detail.type: 'block', 'update' (<main>) or 'rerender' (<body>)
  // detail.uid: the block, for 'block'
  // detail.elements: what was patched; empty when a block was removed
  detail.elements.forEach(el => initWidgets(el))
})
```

<!-- usage-rules:end -->

## Recovery and sharing

The selected view belongs to the preview session. A reconnect restores that
selection alongside form recovery, and an opened standalone window uses the
same view. Shared previews render the currently selected target into a stored,
expiring snapshot; later edits and view changes do not modify that snapshot.
See [Authorization](authorization.md) for ownership, export access, and
revocation behavior.

When adding a target, verify an unsaved edit, a new entry, a cached collection
assign after editing, switching back, reconnect recovery, and the shared output.
The repository's consumer example is `e2e/lib/e2e_project_web/live_preview.ex`;
`e2e/playwright/tests/blocks/block-preview-targets.spec.js` exercises these
editor transitions. If rendering fails, check the application logs and ensure
that required preloads and template/layout assigns match the controller path.

## What the preview page can reach

The preview is served from the admin's own host at `/__livepreview` and renders
with the site's own scripts. Content markup in it (HTML and SVG refs, module
code) runs there too, so every preview response is sandboxed with the
Content-Security-Policy directive
`sandbox allow-scripts allow-forms allow-modals allow-downloads allow-popups allow-popups-to-escape-sandbox`,
and the admin's preview frames carry the same flags in their `sandbox`
attribute. The page's origin is opaque (`null`), not the admin's:

- It cannot read the admin page that frames it. A standalone preview opens
  with no `window.opener`.
- Its requests carry none of the viewer's `SameSite=Lax` or `Strict` cookies,
  and it cannot read a response from the admin. Set `same_site: "Lax"` on the
  endpoint's session options, as `phx.new` does: some browsers (Firefox)
  treat a cookie without it as `None` and send it, though the page still
  cannot read what comes back.
- It cannot navigate the admin page. Links that open a new window open
  outside the sandbox, as they would from any other site.

The rest of the policy is `frame-ancestors 'self'; base-uri 'self'`: only
admin pages on the same origin can frame a preview, and a `<base>` tag in
content cannot redirect the page's relative URLs. Shared preview links
(`/__p__/…`) get the same `sandbox` directive, ahead of the policy the site's
router pipeline sets.

The page's script connects to a socket of its own, which the endpoint
mounts next to the admin socket:

```elixir
socket "/__livepreview/socket", BrandoAdmin.LivePreviewSocket,
  websocket: [check_origin: false],
  longpoll: false
```

It connects with a token for that preview alone
(`Brando.LivePreview.SocketToken`): it names the viewer, their session, the
preview, and the site and environment it belongs to, and it lasts 15
minutes. It joins that preview's channel and no other, and the channel hands
the page a fresh token before the last one expires. The socket takes origin
`null` because it reads no cookie; the admin socket at `/admin/socket` keeps
Phoenix's origin check and refuses preview tokens. The viewer's admin socket
token is not in the page.

Without the line, the preview shows the page as it was when it opened, and
the preview panel says live updates are unavailable; the server log names
the line to add.

### The site's scripts in the preview

Most frontend code runs unchanged. What an opaque origin changes:

- `localStorage`, `sessionStorage` and `document.cookie` work, but hold their
  values in memory for the life of the page. Brando puts stand-ins for them
  in the page (`/__livepreview/storage-<hash>.js`, first in `<head>`); without
  them, reading them throws.
- IndexedDB, the Cache API and service workers are not available.
- Module scripts, fonts and anything else loaded with CORS (`crossorigin`,
  `fetch`) count as cross-origin requests. `Brando.Plug.SiteAssets` sends the
  site's static files with `Access-Control-Allow-Origin: *`, so it must sit
  right before the endpoint's `Plug.Static`, as `mix brando.install` and
  `mix brando.migrate55` put it. A script that fetches from the site's own
  routes (an API, a JSON feed) gets no response in the preview unless that
  route sends the header too. With the Vite dev server in development, allow
  any origin in its `server.cors` setting.

### Restricting scripts further

The preview's own scripts load from `/__livepreview/`, so `'self'` allows
them. To add directives, such as a `script-src` listing the hosts your
templates load scripts from:

```elixir
config :brando, :live_preview_content_security_policy,
  "script-src 'self' https://cdn.example.com; object-src 'none'"
```

The value is appended to the default policy. A `script-src` without
`'unsafe-inline'` also blocks inline `<script>` elements and `on…` attributes
in your templates and in editor content; list your own inline scripts by hash
if the templates need them. `'self'` also allows any script file served from
the same origin, uploaded media included, so where editors can upload files,
list your script directories (such as `https://example.com/assets/`) instead
of `'self'`, along with `https://example.com/__livepreview/` for the
preview's own scripts.

### What protects the admin, and what is left

Three things keep markup an editor writes from acting as someone who views
it:

- The sandbox above, for previews (drafts and unsaved edits) and shared
  preview links.
- Who writes markup that runs. Only superusers write markup that runs as
  written: module code, the template and parameters of an HTML ref, the code
  of an SVG ref ([HTML refs](block_editor.md#html-refs)) and a fragment's
  wrapper. What other editors write is escaped or sanitized before it reaches
  the page: text and rich-text refs, headings, Markdown, captions, vars and an
  HTML ref's parameter values (see
  [Writing templates safely](block_editor.md#writing-templates-safely)).
- Uploads. `Brando.Plug.Media` serves `/media` with
  `Content-Security-Policy: sandbox` and `nosniff`, so an uploaded SVG or HTML
  file opened on its own, from a preview or anywhere else, runs no script
  ([How media is served](media.md#how-media-is-served)).

What is left:

- Published content runs on the site's own pages, outside any sandbox, for
  everyone who visits them. On a site served from the admin's host that
  includes signed-in admins, frontend edit mode included: a script a
  superuser published there has the visiting admin's cookies and can load
  admin pages as them.
- A web server or CDN that serves `/media` itself, rather than through the
  plug, must send the same headers (`Brando.Plug.Media.media_headers/1`).
  Without them, an uploaded SVG opened on its own runs on the site's origin,
  and a preview's standalone window can navigate itself to one.
- To limit which scripts run in previews further, set a `script-src` (above).
