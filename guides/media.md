# Images, files, and galleries

Brando stores media as asset records and lets content fields refer to them. The
asset browser helps editors reuse those records; the field or block drawer owns
the settings for that particular use. Upload completion and saving the content
entry are separate steps.

This walkthrough adds a cover, PDF, and mixed gallery to an existing
`MyApp.Catalog.Product` Blueprint. It assumes working [Blueprint forms](blueprint_forms.md),
a writable media directory, a running image-processing queue, and the consumer's
compiled admin assets. Run a [Blueprint migration](blueprint_migrations.md) after
adding the asset fields.

<!-- usage-rules:start topic="media" -->

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

<!-- usage-rules:end -->

Add `input :cover, :image, label: t("Cover")` inside a form fieldset. Upload a
landscape image, wait for processing, select a focal point in the image editor,
and inspect the square thumbnail. `crop: true` uses the configured geometry and
focal point for the crop; an uncropped size preserves the source proportions.
Save the product and reopen it before checking the public page.

Brando uses `Brando.Images.Processor.Vix` through the Image library and
libvips. Configure it in the consumer if overriding an older processor:

```elixir
config :brando, Brando.Images, processor_module: Brando.Images.Processor.Vix
```

There is no `sharp-cli` step in this pipeline. Keep libvips/Vix supported by your
runtime and build image; test processing on the deployment platform. Size and
MIME limits apply to incoming uploads, while `formats` controls processed output.
For SVG, use an explicitly allowed MIME type and inspect its rendering separately
from raster variants.

<!-- usage-rules:start topic="media" -->

To use application defaults instead, declare `cfg: :default` and configure
`default_config` under `Brando.Images`.

A size takes `"size"` (a geometry such as `"700"`, `"x400"` or `"400x400>"`),
`"quality"` (1–100), `"crop"` and `"ratio"` (`"3/2"`, needed when a cropped
size gives only a width or a height). Atom keys and `%Brando.Images.Size{}` work
too. A Blueprint's literal config is checked when it compiles: a mistyped key
such as `"crp"`, an unreadable geometry, or a `srcset` naming a size that isn't
in `sizes` fails the build with the field and the size it is about. Configs
from a function or `config_target` are checked when they are first read.

`"700"` makes an image 700 pixels wide and `"x400"` 400 tall, the other side
following its proportions, for portraits and landscapes alike; `"700x400"`
fits it inside the box. No size is made larger than the original: from an
original 600 pixels wide, `"1400"` gives a 600-pixel file. A cropped size is
cut to exactly its geometry around the focal point, or, from an original
smaller than the geometry, to the largest part of it with the geometry's
proportions. A trailing `>` ("only shrink") is accepted and changes nothing.
`srcset` widths are written by hand and are not checked against the files, so
`{"large", "1400w"}` is declared 1400 wide even when the original is
narrower. See `Brando.Images.Size`.

<!-- usage-rules:end -->

`sizes` replaces the default list rather than merging with it. To start from
the standard list (micro, thumb, small, medium, large and xlarge) instead of
copying it, name the preset, alone or with sizes to add or replace:

```elixir
asset :cover, :image,
  cfg: %{
    upload_path: "images/products/covers",
    sizes: {:standard, %{"hero" => %{"size" => "2400", "quality" => 80}}},
    srcset: %{default: [{"small", "700w"}, {"large", "1700w"}, {"hero", "2400w"}]}
  }
```

When a config replaces `sizes` without its own `srcset`, the inherited default
`srcset` is dropped if it names sizes the config no longer has.

Changing size definitions does not regenerate existing images by itself. Each
processed image records a fingerprint of the sizes and formats it was made
with, and **Utilities → Image sizes** counts the images whose config has changed
since; **Recreate changed images** reprocesses only those. Confirm the new size
paths exist before rendering them. A requested size absent from `image.sizes`
is a configuration/processing error, not a fallback image.

### Images made before fingerprints

Images processed before Brando stored fingerprints (0.54 and earlier) have
none, and count as changed until they are either recreated or adopted.
Adopting checks an image's stored files against its current config, reading
only their headers, and records the config's fingerprint when they match:

```shell
mix brando.images.adopt --dry-run   # count only
mix brando.images.adopt             # record the ones that match
mix brando.images.adopt --verbose   # and say why the others differ
```

An image matches when its formats are the ones its config produces, its
sizes have exactly the config's size keys, every size exists in every format
in the media folder, and each size's pixel dimensions are what its geometry
gives for the original (scaled, or cropped), within a pixel. Files from the
older processors match too: the sharp-based one of 0.54 and earlier, and the
first libvips one, which 0.55 used before its release and which fitted a
width alone into a square and enlarged smaller originals. Quality and other
encoder settings are not in a file's header and are not compared, nor is a
crop's focal point: if a config changed
only those, use **Recreate image sizes**. Images on the CDN without a local
copy (`keep_local_copy: false`) can't be checked and are left as they are.

The task covers every environment of every active site and is safe to run
again. **Recreate changed images** adopts the same way before recreating, so
from the admin only the images that differ are recreated; it reports how many
of each. `mix brando.doctor` shows the split as a dry run. See
`Brando.Images.Adoption`.

<!-- usage-rules:start topic="media" -->

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

<!-- usage-rules:end -->

The image's alt text is the default; `alt: "..."` overrides it for this placement,
and `alt: ""` marks a decorative image. An image's alt text, title and credits
are kept per content language: the component renders the request's language
(set by `Brando.Plug.I18n`), falling back to the default language. Pass
`language: "no"` to choose it. To read the text yourself, use
`Brando.Images.text(image, :alt, language)` — the fields hold maps of
language → text, not strings (`:i18n_string`; see
[Languages](i18n.md#translated-strings-in-one-field)). It returns that language's text, else the default language's,
else `nil`. `Brando.Images.resolve_texts(image, language)` replaces all three
maps with text in one step and leaves a placement's override strings alone;
call it once where the language is known, and nothing downstream sees a map.
For Liquid, `Brando.Villain.map_images(images, language)` maps images with
their texts resolved (the default language when `nil`).

Use a meaningful caption only when it adds information. `caption: true` uses
the image title; a string supplies an explicit caption. Captions are rendered
as HTML, so only pass trusted editorial content.
A nil image renders nothing. An **unloaded** association renders a diagnostic:
fix the preload rather than hiding it with a CSS rule.

<!-- usage-rules:start topic="media" -->

A template in the database that prints an image text directly shows the raw
map. Add the `i18n` filter, which prints the page's language with the default
as fallback and leaves plain strings alone:

```liquid
{{ entry.cover.alt | i18n }}
```

`{% picture %}` needs nothing. `mix brando.check.image_texts` lists module,
container and menu templates that print `alt`, `title` or `credits` without
the filter, in every active site and environment. It changes nothing and
matches by name, so check each finding.

<!-- usage-rules:end -->

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

<!-- usage-rules:start topic="media" -->

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

Unlike an image field, a gallery's `sizes` are merged into the default sizes
rather than replacing them: the gallery above keeps the default sizes and
changes `"large"`.

<!-- usage-rules:end -->

Add `input :gallery, :gallery, label: t("Gallery")`. Insert an image and a video,
change their order, edit their per-use metadata, and save/reopen the product.
A legacy flat gallery config is interpreted as image configuration; it does not
configure videos. Gallery block refs also expose `allowed_types` to limit the
picker to images, videos, or both. For hosted/transcoded video, configure one of
the supported strategies in [Videos](videos.md); choosing a provider also requires
its credentials and webhook integration.

<!-- usage-rules:start topic="media" -->

Preload and resolve the gallery before passing it to the template:

```elixir
entry = Brando.Repo.preload(entry,
  gallery: [gallery_objects: [:image, video: [:thumbnail, :file]]]
)
media = Brando.Villain.Parser.gallery_media(entry.gallery)
conn = Plug.Conn.assign(conn, :gallery_media, media)
```

<!-- usage-rules:end -->

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
reused. Reusing the original `gallery_id` shares the gallery itself. A context's
generated `duplicate_*` mutation already does this for the entry's gallery
assets and for galleries on block refs and vars. Verify that reordering a
duplicate does not reorder its source.

## Uploads from a site's own forms

A form on the site itself — an application portal where visitors attach
images and a CV — uses `Brando.Uploads.Direct`, the admin's
browser-to-bucket transport without an admin user or the UploadManager.

Give the field a direct CDN config, and keep visitors' files out of the media
library with `hidden_folder`:

```elixir
asset :image, :image,
  cfg: %{
    upload_path: "images/submissions",
    allowed_mimetypes: ["image/jpeg"],
    size_limit: 3_000_000,
    sizes: %{"thumb" => %{"size" => "350x350>", "quality" => 85}},
    hidden_folder: "submissions",
    cdn: %Brando.CDN.Config{enabled: true, direct: true, bucket: "my-bucket",
      media_url: "https://my-bucket.ams3.digitaloceanspaces.com", s3: :default}
  }
```

Then, in a controller the site authorizes itself:

```elixir
# The browser names the file
{:ok, upload} =
  Brando.Uploads.Direct.presign(:image, "image:MyApp.Submissions.Photo:image", %{
    name: "photo.jpg", size: 1_234_567, type: "image/jpeg"
  })

# Hand upload.upload_url and upload.upload_headers to the browser, which
# PUTs the file; keep upload.ref, signed (Phoenix.Token), to know which
# entry the upload belongs to.

# The browser says it is done
{:ok, image} = Brando.Uploads.Direct.complete(upload.ref)
```

`presign/4` answers `{:ok, :server}` for a field without a direct CDN; take
the bytes yourself then and store them with `Brando.Uploads.store_upload/4`
(and processing images with `Brando.Upload.process_upload/3`).

`complete/2` trusts only what `presign/4` recorded: the key, the field and the
declared size and type, which the bucket's own metadata must match. Images
are processed in the background; files and videos are ready at once. An
upload never completed is reaped with its object. Uploads run as `:system`
and have no creator. Who may upload to what is the site's to decide.

Media in a hidden folder is not listed in the image, file or video library,
counted on the alt-text page, or offered by the image picker's browse-all.
It is still public at its URL, like all media.

## Tidy a folder that has filled up

Block images all upload to the default config's folder (`images/site/default`
unless you changed it), so over the years it becomes one long list. The image
library can sort it from where the images are used.

Open the folder under **Resources → Images** and choose **Sort by use**. The
preview lists a folder per entry that uses images from this one, named by type
and title (`cases/sommerro`, `pages/about`), with some of its images. Untick
the ones to leave, rename the folders you want different, and move them. The
bar above the list offers **Undo** until you leave the page.

- Only images directly in the folder are sorted; what is already in a subfolder
  stays, so a later run takes only what has arrived since.
- An entry and its translations share a folder, named after the entry in the
  default language.
- Images no entry uses stay where they are. Switch on **Not in use** to see
  them; with it on, the header offers to delete all of them (a soft delete).
- A move changes the image's folder, not its files, so no URL changes.

An image several entries use goes to one of them: the entry using the most of
the folder's images, unless the site ranks its types:

```elixir
config :brando, Brando.Images,
  sweep_priority: [MyApp.Projects.Project, MyApp.Articles.Article, Brando.Pages.Page]
```

## What happens to a deleted image's files

Deleting an image or a file is a soft delete: the row is marked and the files
stay, so it can be restored. Thirty days later the nightly purge removes the
row. The files are removed by a separate nightly job,
`Brando.Worker.MediaOrphanCleanup`, which deletes what no image or file row
references any more, soft-deleted rows included. It leaves SVGs, dotfiles,
symlinks and anything changed in the last 24 hours alone, and only looks under
`images`, `videos` and `files`.

With [tenancy](tenancy_and_environments.md) the job always runs. A site
without tenancy switches it on:

```elixir
config :brando, media_orphan_cleanup: true
```

It is off by default because such a site can keep files of its own under the
media root that no row knows of, and those would go. See what a run would
remove first:

```elixir
{:ok, report} = Brando.Media.OrphanCleanup.run(nil, dry_run: true)
length(report.deleted)
```

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
