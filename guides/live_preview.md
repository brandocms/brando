# Live preview

Live preview renders the current unsaved entry through your application's own
Phoenix templates and layout. Editors can inspect a page at desktop, tablet, or
mobile dimensions, open the preview in another window, and create an expiring
shared snapshot when they have export access.

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
view opens immediately from the editor's eye button; existing unnamed targets
continue to work without changes.

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
- `rerender_on_change [[:field]]` requests a full-page render when changes affect
  markup outside individual block regions. `template_section` and
  `template_css_classes` accept a string or an entry callback for layout context.

Templates receive `@LIVE_PREVIEW` and a preview connection. Reuse production
markup where possible. Collection callbacks receive preloaded, unsaved data
before block HTML is rendered; cards should use their normal metadata rather
than assuming freshly rendered block HTML is already present in the callback.

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
`e2e/e2e/playwright/tests/blocks/block-preview-targets.spec.js` exercises these
editor transitions. If rendering fails, check the application logs and ensure
that required preloads and template/layout assigns match the controller path.
