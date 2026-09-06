# Images, files, and galleries

Brando stores media as asset records and lets content fields refer to them. The
asset browser helps editors reuse those records; the field or block drawer owns
the settings for that particular use. Upload completion and saving the content
entry are separate steps.

This walkthrough adds a cover, PDF, and mixed gallery to an existing
`MyApp.Catalog.Product` Blueprint. It assumes working [Blueprint forms](blueprints.md),
a writable media directory, a running image-processing queue, and the consumer's
compiled admin assets. Run a [Blueprint migration](blueprint_migrations.md) after
adding the asset fields.

## Configure a cover image

In the Blueprint's `assets` section:

```elixir
asset :cover, :image,
  cfg: %{
    upload_path: "images/products/covers",
    allowed_mimetypes: ["image/jpeg", "image/png", "image/webp"],
    size_limit: 10_000_000,
    random_filename: true,
    formats: [:original, :webp],
    default_size: "large",
    sizes: %{
      "thumb" => %{"size" => "400x400>", "crop" => true, "quality" => 80},
      "small" => %{"size" => "700", "quality" => 80},
      "large" => %{"size" => "1400", "quality" => 80}
    },
    srcset: %{default: [{"small", "700w"}, {"large", "1400w"}]}
  }
```

Add `input :cover, :image, label: t("Cover")` inside a form fieldset. Upload a
landscape image, wait for processing, select a focal point in the image editor,
and inspect the square thumbnail. `crop: true` uses the configured geometry and
focal point for the crop; an uncropped size preserves the source proportions.
Save the product and reopen it before checking the public page.

Brando 0.54 uses `Brando.Images.Processor.Vix` through the Image library and
libvips. Configure it in the consumer if overriding an older processor:

```elixir
config :brando, Brando.Images, processor_module: Brando.Images.Processor.Vix
```

There is no `sharp-cli` step in this pipeline. Keep libvips/Vix supported by your
runtime and build image; test processing on the deployment platform. Size and
MIME limits apply to incoming uploads, while `formats` controls processed output.
For SVG, use an explicitly allowed MIME type and inspect its rendering separately
from raster variants.

To use application defaults instead, declare `cfg: :default` and configure
`default_config` under `Brando.Images`. Field configs are normalized and checked
at compilation; malformed sizes or unsupported formats should fail early.
Changing size definitions does not magically regenerate every existing image.
Reprocess affected assets and confirm the new size paths exist before rendering
them. A requested size absent from `image.sizes` is a configuration/processing
error, not a fallback image.

## Render responsive images

Preload the asset in the controller's query or through the repo:

```elixir
entry = Brando.Repo.preload(entry, [:cover, :brochure])
```

Then render the cover:

```heex
<Brando.HTML.picture
  src={@entry.cover}
  opts={[
    prefix: Brando.Utils.media_url(),
    size: "large",
    srcset: {MyApp.Catalog.Product, :cover},
    sizes: ["(min-width: 70rem) 60vw", "100vw"],
    lazyload: false,
    fetchpriority: "high"
  ]}
/>
```

Use actual output-width descriptors in `srcset` and a `sizes` expression matching
the layout. Do not label a 700-pixel rendition `1400w`. For below-the-fold images,
`lazyload: true` and a supported placeholder use the consumer's Jupiter lazyload
integration; verify that integration before depending on deferred `data-srcset`
attributes. The example above works without that deferred-loading behavior.

The image's alt text is the default; `alt: "..."` overrides it for this placement,
and `alt: ""` marks a decorative image. Use a meaningful caption only when it adds
information. `caption: true` uses the image title; a string supplies an explicit
caption. Captions are rendered as HTML, so only pass trusted editorial content.
A nil image renders nothing. An **unloaded** association renders a diagnostic:
fix the preload rather than hiding it with a CSS rule.

For a plain URL, use
`Brando.Utils.img_url(image, "large", prefix: Brando.Utils.media_url())`.
The helper honors the asset's CDN state and configuration; concatenating
`image.path` with a hostname does not handle size or CDN selection.

## Add a PDF download

In the same `assets` section:

```elixir
asset :brochure, :file,
  cfg: %{
    upload_path: "files/products/brochures",
    allowed_mimetypes: ["application/pdf"],
    size_limit: 20_000_000,
    random_filename: false,
    slugify_filename: true,
    overwrite: false,
    content_disposition: :attachment
  }
```

Add `input :brochure, :file, label: t("Brochure")`. Upload a PDF, save the product,
and reopen it. To render the preloaded asset:

```heex
<a :if={@entry.brochure}
   href={Brando.Utils.file_url(@entry.brochure, prefix: Brando.Utils.media_url())}>
  Download brochure ({Brando.Utils.human_size(@entry.brochure.filesize)})
</a>
```

Use the two-argument `file_url/2` form with a media prefix for local/CDN-aware
links. The older one-argument helper builds a local media URL. `content_disposition`
sets the object header during CDN upload; it does not change your local static
server's response headers. `:inline` requests browser display, such as an inline
PDF, while `:attachment` requests download.

**Selecting another file in a field** changes that field's association when the
entry is saved. **Replacing an asset's bytes** through the file browser keeps its
record, URL, metadata, folder, and existing references. The latter intentionally
affects every use of that asset. A failed replacement retains the original.
If a stable URL is cached outside Brando, refresh the CDN/browser cache after a
replacement; Brando cannot invalidate an arbitrary proxy automatically.

Removing an optional field association is not permanent deletion of the shared
asset. A `required: true` asset must remain present for a valid publishable entry.
A rejected MIME type or size should leave the previous selection in place; test
that state as well as the successful upload.

## Add an ordered mixed gallery

A gallery has its own row and ordered `gallery_objects`; each object points to
an image or video and carries per-placement configuration. Configure the two
media types independently:

```elixir
asset :gallery, :gallery,
  cfg: %{
    image: %{
      upload_path: "images/products/gallery",
      size_limit: 12_000_000,
      sizes: %{"large" => %{"size" => "1400", "quality" => 80}},
      default_size: "large"
    },
    video: %{
      upload_path: "videos/products/gallery",
      allowed_mimetypes: ["video/mp4", "video/webm"],
      size_limit: 200_000_000,
      upload_strategy: :local
    }
  }
```

Add `input :gallery, :gallery, label: t("Gallery")`. Insert an image and a video,
change their order, edit their per-use metadata, and save/reopen the product.
A legacy flat gallery config is interpreted as image configuration; it does not
configure videos. Gallery block refs also expose `allowed_types` to limit the
picker to images, videos, or both. For hosted/transcoded video, configure one of
the supported strategies in [Videos](videos.md); choosing a provider also requires
its credentials and webhook integration.

Preload and resolve the gallery before passing it to the template:

```elixir
entry = Brando.Repo.preload(entry,
  gallery: [gallery_objects: [:image, video: [:thumbnail, :file]]]
)
media = Brando.Villain.Parser.gallery_media(entry.gallery)
conn = Plug.Conn.assign(conn, :gallery_media, media)
```

```heex
<div :if={@gallery_media != []} class="product-gallery">
  <%= for {type, asset} <- @gallery_media do %>
    <%= case type do %>
      <% :image -> %>
        <Brando.HTML.picture src={asset}
          opts={[prefix: Brando.Utils.media_url(), size: "large", caption: true]} />
      <% :video -> %>
        <Brando.HTML.video video={asset} opts={[]} />
    <% end %>
  <% end %>
</div>
```

`gallery_media/1` returns ordered `{:image, image}` / `{:video, video}` pairs and
applies supported object overrides, including image title/alt/credits and video
caption/playback choices. Iterating raw join rows without applying those overrides
can show the shared asset's defaults instead of the editor's chosen values.
A nil or empty gallery produces an empty list; unloaded media is skipped, so a
surprisingly empty gallery is a reason to check preloads.

Gallery ownership matters when duplicating content. Use
`Brando.Galleries.duplicate_gallery(gallery.id, current_user.id)` for an independent
gallery: its join rows and configuration are copied while image/video assets are
reused. Reusing the original `gallery_id` shares the gallery itself. Verify that
reordering a duplicate does not reorder its source.

## Upload lifecycle and delivery checks

The sticky UploadManager owns intake, transfer, validation, progress, and delivery
back to the originating field, block ref, var, or gallery. Uploading an asset does
not save the parent entry. Keep the manager's normal integration when customizing
a field instead of adding a second upload channel inside the form.

An asset can finish transferring before image processing or provider encoding
finishes. Completion callbacks run after the relevant processing/storage milestone
and may retry; make their side effects idempotent. A callback that needs the
parent entry should not assume that the editor has saved its new association yet.

Check a real consumer: upload, wait for readiness, save, reload, inspect the
rendered `src`/`srcset` or download URL, and request the returned asset. Repeat with
an invalid upload, removal, replacement, gallery reordering, and duplication.
Use [CDN delivery](cdn.md) for remote storage and
[content lifecycle](content_lifecycle.md#deletion-and-restoration) for retention.
