## Videos

Brando supports video fields with multiple upload strategies for different hosting providers.

### Video Fields in Blueprints

Define a video field in your schema's assets:

```elixir
assets do
  asset :video, :video,
    cfg: %{
      upload_strategy: :mux,
      allowed_mimetypes: ["video/mp4", "video/webm", "video/quicktime"],
      size_limit: 500_000_000,
      meta: %{
        mux: %{
          "max_resolution_tier" => "1080p",
          "playback_policies" => ["public"]
        }
      }
    }
end
```

### Add webhook to your endpoint

Webhook plugs must come BEFORE `Plug.Parsers` to read raw body for signature verification.

#### Mux

```elixir
plug BrandoWeb.Plugs.MuxWebhook,
  mount: ["api", "videos", "mux", "webhook"]

plug Plug.Parsers, #...
```

#### Bunny Stream

```elixir
plug BrandoWeb.Plugs.BunnyWebhook,
  mount: ["api", "videos", "bunny", "webhook"]

plug Plug.Parsers, #...
```

#### Cloudflare Stream

```elixir
plug BrandoWeb.Plugs.CloudflareStreamWebhook,
  mount: ["api", "videos", "cloudflare", "webhook"]

plug Plug.Parsers, #...
```

### Upload Strategies

The `upload_strategy` determines where videos are uploaded:

| Strategy      | Description |
|---------------|-------------|
| `:local`      | Traditional server upload, files stored on server/CDN (default) |
| `:s3`         | Direct original-file upload to S3-compatible storage; no transcoding |
| `:mux`        | Direct upload to Mux for streaming |
| `:bunny`      | Direct upload to Bunny Stream with TUS resumable uploads |
| `:cloudflare` | Direct resumable upload to Cloudflare Stream |

Only implemented strategies are accepted during Blueprint compilation. S3 stores
the original video and creates a normal `:upload` Video; use Mux, Bunny, or
Cloudflare when adaptive streaming/transcoding is required.

### Global Default Strategy

Set a default upload strategy for video blocks and other contexts that don't have a specific field config:

```elixir
# config/config.exs
config :brando, :default_video_upload_strategy, :mux
```

When not configured, defaults to `:local`.

This setting affects:
- Video blocks in the Villain editor
- Any video picker without a specific config target

### Mux Configuration

For Mux uploads, you need to configure your credentials:

```elixir
# config/config.exs
config :brando, Brando.Videos.Uploaders.Mux,
  access_token_id: System.get_env("MUX_TOKEN_ID"),
  access_token_secret: System.get_env("MUX_TOKEN_SECRET"),
  webhook_secret: System.get_env("MUX_WEBHOOK_SECRET")
```

#### Mux Provider Settings

Available settings via `meta.mux`:

| Setting | Description | Values |
|---------|-------------|--------|
| `max_resolution_tier` | Maximum transcoding resolution | `"1080p"` (Brando default), `"1440p"`, `"2160p"` |
| `video_quality` | Encoding quality level | `"basic"`, `"plus"`, `"premium"` |
| `playback_policies` | Who can view the video | `["public"]` |
| `static_renditions` | Generate downloadable renditions | `[%{"resolution" => "highest"}]` |

`max_resolution_tier` accepts only the three values above — Mux rejects anything
else (`"720p"`, `"480p"`) with `Invalid max resolution tier value`. Set it to
`nil` to drop it from the request entirely and let Mux pick based on the source.

`video_quality` (formerly `encoding_tier`, where `basic` was `baseline` and
`plus` was `smart`) has no Brando default. When unset, Mux applies the
organization default — `basic` for newer accounts, `plus` for older ones — so
set it explicitly if encoding cost matters. `basic` uses a reduced encoding
ladder at a lower target quality; `plus` and `premium` use per-title encoding.

Brando merges `meta.mux` into Mux's `new_asset_settings` verbatim, so any other
setting the Mux asset API accepts can be passed here as well. Only
`playback_policies` is validated up front; other invalid values surface as a Mux
API error when the upload is initiated, not at compile time.

Signed Mux playback is rejected until the application provides a token-signing
boundary. Legacy `playback_policy` and `mp4_support` settings are translated to
the current Mux request fields, but new configuration should use the fields above.

### Bunny Stream Configuration

For Bunny Stream uploads, configure your credentials:

```elixir
# config/runtime.exs
config :brando, Brando.Videos.Uploaders.Bunny,
  api_key: System.get_env("BUNNY_API_KEY"),
  webhook_secret: System.get_env("BUNNY_READ_ONLY_API_KEY"),
  library_id: System.get_env("BUNNY_LIBRARY_ID"),
  cdn_hostname: System.get_env("BUNNY_CDN_HOSTNAME")
```

#### Environment Variables

| Variable | Description |
|----------|-------------|
| `BUNNY_API_KEY` | Your Bunny Stream Library API key |
| `BUNNY_READ_ONLY_API_KEY` | Read-Only API key used to verify Bunny webhook signatures |
| `BUNNY_LIBRARY_ID` | Your Video Library ID (numeric) |
| `BUNNY_CDN_HOSTNAME` | CDN hostname for HLS playback (e.g., `vz-abc123.b-cdn.net`) |

#### Webhook Setup

Configure the webhook URL in your Bunny Stream dashboard:

```
https://yoursite.com/api/videos/bunny/webhook
```

Bunny will send status updates when videos finish encoding. The webhook plug
rejects requests unless the `v1` HMAC signature validates against
`webhook_secret` (the library Read-Only API key).

> #### Bunny deliveries can be replayed {: .warning}
>
> Unlike Mux and Cloudflare, **Bunny's signature covers the raw body only — it
> carries no timestamp**, so Brando has nothing to check freshness against and
> the other two plugs' 5-minute tolerance has no equivalent here. Anyone who
> captures a valid Bunny delivery can resubmit it indefinitely and it will
> verify.
>
> This is Bunny's own specification, not an omission on our side. Their Stream
> webhook documentation says of the `v1` scheme: *"The URL, timestamp, HTTP
> method, and headers are not part of the v1 signature."* Checked against
> [their docs](https://bunny.net/docs/stream/webhooks) on 2026-08-08; `v1` is
> still the only version they define. If Bunny ever ships a `v2` that signs a
> timestamp, this plug should adopt it and gain the tolerance check that
> `MuxWebhook` and `CloudflareStreamWebhook` already have.
>
> This is a property of Bunny's signing scheme, not a gap in the plug. The
> exposure is bounded: a replayed webhook re-applies a status Bunny already
> sent for a video the site already owns, so the realistic effect is a video
> being moved back to an earlier encoding status. It cannot introduce a video,
> retarget one, or carry an attacker's payload, because the body is signed.
>
> Terminate TLS in front of the endpoint so deliveries are not capturable in
> transit, and treat the Read-Only API key as the secret it is.

#### Bunny Blueprint Example

```elixir
assets do
  asset :video, :video,
    cfg: %{
      upload_strategy: :bunny,
      allowed_mimetypes: ["video/mp4", "video/webm", "video/quicktime"],
      size_limit: 500_000_000
    }
end
```

#### Playback URLs

Bunny videos are served via HLS streaming:

```elixir
# Get playback URL for a video
{:ok, url} = Brando.Videos.Uploaders.Bunny.get_playback_url(video)
# => "https://vz-abc123.b-cdn.net/{video_guid}/playlist.m3u8"

# Get embed iframe URL
{:ok, url} = Brando.Videos.Uploaders.Bunny.get_embed_url(video)
# => "https://iframe.mediadelivery.net/embed/{library_id}/{video_guid}"
```

### Cloudflare Stream Configuration

```elixir
# config/runtime.exs
config :brando, Brando.Videos.Uploaders.Cloudflare,
  account_id: System.get_env("CLOUDFLARE_ACCOUNT_ID"),
  api_token: System.get_env("CLOUDFLARE_STREAM_API_TOKEN"),
  webhook_secret: System.get_env("CLOUDFLARE_STREAM_WEBHOOK_SECRET"),
  delete_remote_on: :on_purge
```

The API token needs Stream write access. Register the public webhook URL once
for the Cloudflare account; Cloudflare returns the signing secret used above.
The plug verifies `Webhook-Signature` against the exact raw body and rejects
stale timestamps. Cloudflare permits one Stream webhook subscription per
account.

```elixir
asset :video, :video,
  cfg: %{
    upload_strategy: :cloudflare,
    size_limit: 2_000_000_000,
    meta: %{cloudflare: %{"max_duration_seconds" => 3_600}}
  }
```

Cloudflare signed playback is intentionally rejected until the application has
a token-signing boundary. Brando stores the HLS/DASH and thumbnail URLs from the
signed processing webhook rather than constructing a customer hostname.

### S3-compatible Original Video Storage

`:s3` requires an explicit direct CDN config on the video config. `media_url`
must be the public origin for the bucket; bucket CORS must allow `PUT` from the
admin origin and allow the signed `Content-Type` header (plus `x-amz-acl` only
when `direct_acl` is configured).

```elixir
asset :video, :video,
  cfg: %{
    upload_strategy: :s3,
    upload_path: "videos/projects",
    size_limit: 2_000_000_000,
    cdn: %Brando.CDN.Config{
      enabled: true,
      direct: true,
      bucket: System.fetch_env!("VIDEO_BUCKET"),
      media_url: System.fetch_env!("VIDEO_MEDIA_URL"),
      s3: :default
    }
  }
```

The server signs the exact content type. After the browser PUT completes, it
HEADs the server-owned key and verifies `Content-Length` and `Content-Type`
before creating the CDN-backed File and ready Video rows. Modern AWS buckets
should use bucket policies/Object Ownership and leave `direct_acl` unset; set it
only for compatible services that explicitly require an object ACL.

### Remote Video Deletion

When videos are deleted from the Brando admin, you can optionally delete the source video from the provider (Mux/Bunny/Cloudflare). Configure this per-uploader:

#### Configuration

```elixir
# config/runtime.exs
config :brando, Brando.Videos.Uploaders.Mux,
  # ... existing config ...
  delete_remote_on: :on_purge

config :brando, Brando.Videos.Uploaders.Bunny,
  # ... existing config ...
  delete_remote_on: :on_purge

config :brando, Brando.Videos.Uploaders.Cloudflare,
  # ... existing config ...
  delete_remote_on: :on_purge
```

#### Options

| Value | Description |
|-------|-------------|
| `:on_delete` | Delete from provider immediately when soft-deleted in admin |
| `:on_purge` | Delete from provider when soft-delete expires after 30 days (default) |
| `false` | Never delete from provider |

#### Behavior

- **`:on_delete`**: When a user deletes a video in the admin, it's immediately removed from its provider. The video cannot be restored from the provider.
- **`:on_purge`** (default): Videos are soft-deleted locally first. After 30 days, when the soft-delete purger runs, the video is permanently deleted from both the database and the provider. This allows video restoration during the grace period.
- **`false`**: Videos are only deleted locally. Provider videos remain and must be manually cleaned up.

### Video Blocks

Video blocks in the Villain editor use the global `default_video_upload_strategy` setting. When set to a non-local strategy (like `:mux`), the video picker will show a file upload option for direct uploads.

The upload flow:
1. User selects a video file in the video picker
2. File is uploaded directly to the provider (e.g., Mux)
3. Video record is created and associated with the block
4. Provider webhooks update the video status when processing completes

### Videos in Galleries

Gallery fields (`asset :my_gallery, :gallery`) hold both images and videos. Videos
can be added to a gallery in three ways:

1. **Select existing videos** — the "Select videos" button opens the video picker.
2. **Add from URL** — the video picker accepts YouTube, Vimeo and direct video URLs.
3. **Upload video files**:
   - With `:local` or a configured `:s3` strategy, the gallery input shows an
     "Upload videos" button that uploads through the unified upload manager and
     appends the video to the gallery.
   - With a provider strategy (`:mux`/`:bunny`/`:cloudflare`), upload through the video picker's
     "Upload file" button instead — the uploaded video is selected into the
     gallery automatically.

Gallery assets can override image and video upload behavior independently:

```elixir
asset :my_gallery, :gallery,
  cfg: %{
    image: %{upload_path: "images/projects/gallery"},
    video: %{
      upload_path: "videos/projects/gallery",
      upload_strategy: :mux,
      size_limit: 500_000_000
    }
  }
```

A legacy flat gallery `cfg` is still treated as the image configuration. Module
gallery refs and gallery vars can further override the image/video config targets
and restrict the allowed media types in their contextual configuration.

### Video Config Options

Full list of `Brando.Type.VideoConfig` options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `upload_strategy` | atom | `:local` | Where to upload videos |
| `upload_path` | string | `"videos/default"` | Path for local uploads |
| `cdn` | `Brando.CDN.Config` or nil | `nil` | Required enabled/direct config for `:s3` |
| `allowed_mimetypes` | list | `["video/mp4", ...]` | Accepted video formats |
| `size_limit` | integer | `100_000_000` | Max file size in bytes |
| `allow_uploads` | boolean | `true` | Enable file uploads |
| `allow_external_urls` | boolean | `true` | Enable URL-based videos |
| `random_filename` | boolean | `false` | Randomize uploaded filenames |
| `slugify_filename` | boolean | `true` | Slugify uploaded filenames |
| `meta` | map | `%{}` | Provider-specific settings |
