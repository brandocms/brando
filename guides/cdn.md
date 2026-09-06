# CDN delivery

A CDN configuration connects three separate things: an S3-compatible storage
endpoint, a bucket/object key, and the public URL used by browsers. Configure and
verify all three. Enabling a CDN does not migrate existing media automatically.

Start with working [local media fields](media.md). You need a bucket, credentials
that permit the chosen upload operations, and a public delivery URL. The examples
use DigitalOcean Spaces-style S3 settings; substitute your storage service's
endpoint and region. Keep secrets in runtime environment variables.

## Configure defaults

In the consumer's `config/runtime.exs`:

```elixir
config :brando, Brando.CDN.S3Config, %Brando.CDN.S3Config{
  access_key_id: System.fetch_env!("MEDIA_ACCESS_KEY_ID"),
  secret_access_key: System.fetch_env!("MEDIA_SECRET_ACCESS_KEY"),
  scheme: "https://",
  host: "ams3.digitaloceanspaces.com",
  region: "ams3"
}

media_cdn = %Brando.CDN.Config{
  enabled: true,
  bucket: System.fetch_env!("MEDIA_BUCKET"),
  media_url: "https://media.example.com",
  s3: :default,
  keep_local_copy: true
}

config :brando, Brando.Images, cdn: media_cdn
config :brando, Brando.Files, cdn: media_cdn
```

Use `%Brando.CDN.Config{}` and `%Brando.CDN.S3Config{}` for these shared settings.
Some upload entry points normalize keyword lists, but the lower-level CDN
helpers expect maps/structs. `s3: :default` resolves the shared connection above;
a missing referenced default raises a configuration error.

Here `media_url` is the public root **before** `/media`. The renderer's media
prefix supplies that part of the path. Pointing it at a URL that already ends in
`/media` can duplicate the segment.

An image field may supply its own `cdn` config inside its asset `cfg`, including
a different bucket and connection. Server-side image uploads honor it. The legacy
server-side **file** uploader still obtains its bucket and S3 connection from
`Brando.Files`, even when a field has a CDN config. Keep those settings aligned
for that transport; use verified direct-upload configuration if field-specific
file storage is required. A field's URL setting alone cannot move its bytes.

## Understand the paths

For a classic installation with `media_path: "/srv/studio/media"`, an image
stored as `images/products/cover.jpg` has these locations:

| Meaning | Example |
| --- | --- |
| Database-relative image path | `images/products/cover.jpg` |
| Local original | `/srv/studio/media/images/products/cover.jpg` |
| S3 object key | `media/images/products/cover.jpg` |
| Public CDN URL | `https://media.example.com/media/images/products/cover.jpg` |

Each processed size has its own stored relative path and object. Files combine
their configured `upload_path` and stored `filename` in the same way. An absolute
filesystem path is never a browser URL, and the S3 service endpoint is not
necessarily your public CDN hostname.

Use the rendering helpers with `prefix: Brando.Utils.media_url()`:

```elixir
Brando.Utils.img_url(image, "large", prefix: Brando.Utils.media_url())
Brando.Utils.file_url(file, prefix: Brando.Utils.media_url())
```

They select a CDN prefix when the record is marked as delivered to the CDN and
its configuration enables it. `Brando.Utils.media_url(file)` is a separate helper:
its global CDN fallback constructs the storage endpoint/bucket URL; use
`file_url/2` when the configured public CDN hostname is required.

In `:multi` tenancy, local media uses `media/{site_key}` while records retain
relative paths. Environments of one site share those bytes. **The site key is
not automatically inserted into the legacy S3 object-key construction.** If
sites share a bucket, configure distinct upload namespaces or buckets and test
for collisions; do not infer remote isolation from local directory isolation.
Job tenant context ensures the correct records/configuration are used, but is
not itself an object-key prefix. See [Sites and environments](tenancy_and_environments.md).

## Server-side and direct uploads

Images are uploaded to the application, processed with Image/Vix, and then queued
for delivery of the original and each generated rendition. The `image_processing`
and `default` queues must run. Keeping local copies is the default and lets you
reprocess later. Changing `keep_local_copy` requires a deliberate retention plan;
it does not create a local copy of a direct upload.

Files and S3 videos can opt into browser-to-bucket upload with
`%Brando.CDN.Config{enabled: true, direct: true, ...}`. The manager obtains a
presigned destination, transfers bytes, and finalizes the pending intent before
creating/attaching the asset. The bucket must permit the browser's origin,
method, and signed request headers through CORS. Leave `direct_acl: nil` unless
your bucket requires an ACL header. Direct uploads do not pass through image
processing, and direct S3 video stores an original rather than transcoding it.
Use [Videos](videos.md) for Mux, Bunny Stream, and Cloudflare Stream instead.

A successful browser transfer is not enough: failed finalization must not be
reported as an attached asset. Preserve the UploadManager's retry/error display.
Abandoned pending uploads are handled by the upload-intent reaper; already
referenced media has a different retention lifecycle.

## Verify delivery

Upload one new image and one new PDF through the consumer admin. Wait for
processing and delivery, save the parent entry, and reload it. Inspect the
rendered URLs and request the actual objects:

```bash
curl -I https://media.example.com/media/files/products/brochures/example.pdf
curl -I https://media.example.com/media/images/products/covers/example.jpg
```

Replace these paths with those returned by your helpers; generated filenames and
rendition directories are not fixed. Check status, content type, file size, and
`Content-Disposition` for the PDF. Request every image URL advertised in `srcset`.
A working original with missing renditions still produces a broken responsive
image.

A `403` points to credentials, policy, ACL, or signing configuration; a `404` can
mean a wrong public prefix/key or an unfinished delivery job. Inspect the failed
job without logging credentials. Existing local-only records remain local until
uploaded. `Brando.CDN.queue_upload(asset, current_user)` is available for a
controlled backfill after processing/configuration have been verified; track
completion before removing any local bytes.

Replacing a file at the same key may require CDN invalidation. Updating
`content_disposition` affects new uploads; the
`mix brando.files.update_content_disposition` task supports a dry run before
rewriting existing object headers. Run `mix help` for its exact target/options.

Frontend build artifacts use `Brando.Static` and the deployment workflow, not
image/file field settings. See [Deployment](deployment.md) and the asset-set
section of [Sites and environments](tenancy_and_environments.md) for that lifecycle.
