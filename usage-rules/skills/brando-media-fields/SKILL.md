---
name: brando-media-fields
description: Add or render images, files, videos and galleries in this Brando site. Use when declaring image, file, video or gallery assets on a Blueprint, configuring image sizes and srcsets, rendering media in templates, or handling uploads from the site's own forms.
---

# Brando media fields

Media are asset records. Content fields, block refs and vars refer to them,
and each use keeps its own settings (caption, crop, playback). Upload and
saving the entry are separate steps.

## Read first

- `deps/brando/usage-rules.md`: the Images, files, and galleries and Videos
  sections.
- `deps/brando/guides/media.md`, `videos.md`, `cdn.md`.

## Declare and render

```elixir
assets do
  asset :cover, :image, cfg: :default
end
```

Add `input :cover, :image, label: t("Cover")` to a form fieldset, generate a
Blueprint migration, and preload the asset before rendering it
(`Brando.Repo.preload(entry, [:cover])`).

## Rules that bite

- A literal image config is checked when the Blueprint compiles: unknown keys,
  unreadable geometries and `srcset` entries naming missing sizes fail the
  build.
- `sizes` replaces the default list. Use `{:standard, %{...}}` to extend the
  standard sizes instead.
- Changing sizes does not reprocess existing images; **Utilities → Image
  sizes** recreates the changed ones.
- A size missing from `image.sizes` is a configuration or processing error,
  not a fallback.
- Image processing needs libvips in the runtime and build image.
