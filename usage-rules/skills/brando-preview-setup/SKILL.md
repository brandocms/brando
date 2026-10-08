---
name: brando-preview-setup
description: Configure Brando live preview for this site's content types. Use when adding or changing preview targets in the site's LivePreview module, when a preview renders the wrong layout, template or assigns, or when a preview does not refresh after an edit.
---

# Brando live preview setup

Live preview renders the unsaved entry through the site's own layout and
templates. The site declares one `preview_target` per view in its
`MyAppWeb.LivePreview` module (`use Brando.LivePreview`).

## Read first

- `deps/brando/usage-rules.md`: the Live preview section.
- `deps/brando/guides/live_preview.md`; `frontend_edit.md` if the site uses
  frontend edit mode.

## Add a view

```elixir
preview_target MyApp.Articles.Article do
  label "Article"
  layout {MyAppWeb.Layouts, "app"}
  template {MyAppWeb.ArticleHTML, "show"}
  template_prop :article
end
```

Use the same layout, template and assigns as the controller that renders the
public page. `template_prop` names the assign holding the edited entry
(`:entry` by default). Give each extra target for the same schema a unique
`name`.

## Rules that bite

- Relations an assign callback needs come from the target's preloads, which
  run before the callbacks.
- Assigns are cached separately from rendered HTML: list the fields that
  should refresh an assign in `reassign_on_change`.
- Check a change by opening the preview from the entry form, editing a field
  and watching it update, then reloading the preview window.
