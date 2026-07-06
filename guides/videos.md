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
          "playback_policy" => ["public"]
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

### Upload Strategies

The `upload_strategy` determines where videos are uploaded:

| Strategy      | Description |
|---------------|-------------|
| `:local`      | Traditional server upload, files stored on server/CDN (default) |
| `:mux`        | Direct upload to Mux for streaming |
| `:bunny`      | Direct upload to Bunny Stream with TUS resumable uploads |
| `:cloudflare` | Direct upload to Cloudflare Stream (not yet implemented) |
| `:s3`         | Direct upload to AWS S3 (not yet implemented) |

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
| `max_resolution_tier` | Maximum transcoding resolution | `"1080p"`, `"2160p"` |
| `playback_policy` | Who can view the video | `["public"]`, `["signed"]` |
| `mp4_support` | Generate MP4 files | `"none"`, `"standard"` |

### Bunny Stream Configuration

For Bunny Stream uploads, configure your credentials:

```elixir
# config/runtime.exs
config :brando, Brando.Videos.Uploaders.Bunny,
  api_key: System.get_env("BUNNY_API_KEY"),
  library_id: System.get_env("BUNNY_LIBRARY_ID"),
  cdn_hostname: System.get_env("BUNNY_CDN_HOSTNAME")
```

#### Environment Variables

| Variable | Description |
|----------|-------------|
| `BUNNY_API_KEY` | Your Bunny Stream Library API key |
| `BUNNY_LIBRARY_ID` | Your Video Library ID (numeric) |
| `BUNNY_CDN_HOSTNAME` | CDN hostname for HLS playback (e.g., `vz-abc123.b-cdn.net`) |

#### Webhook Setup

Configure the webhook URL in your Bunny Stream dashboard:

```
https://yoursite.com/api/videos/bunny/webhook
```

Bunny will send status updates when videos finish encoding.

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

### Remote Video Deletion

When videos are deleted from the Brando admin, you can optionally delete the source video from the provider (Mux/Bunny). Configure this per-uploader:

#### Configuration

```elixir
# config/runtime.exs
config :brando, Brando.Videos.Uploaders.Mux,
  # ... existing config ...
  delete_remote_on: :on_purge

config :brando, Brando.Videos.Uploaders.Bunny,
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

- **`:on_delete`**: When a user deletes a video in the admin, it's immediately removed from Mux/Bunny. The video cannot be restored from the provider.
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
   - With the default `:local` strategy, the gallery input shows an
     "Upload videos" button that uploads through the unified upload manager and
     appends the video to the gallery.
   - With a provider strategy (`:mux`/`:bunny`), upload through the video picker's
     "Upload file" button instead — the uploaded video is selected into the
     gallery automatically.

### Video Config Options

Full list of `Brando.Type.VideoConfig` options:

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `upload_strategy` | atom | `:local` | Where to upload videos |
| `upload_path` | string | `"videos/default"` | Path for local uploads |
| `allowed_mimetypes` | list | `["video/mp4", ...]` | Accepted video formats |
| `size_limit` | integer | `100_000_000` | Max file size in bytes |
| `allow_uploads` | boolean | `true` | Enable file uploads |
| `allow_external_urls` | boolean | `true` | Enable URL-based videos |
| `random_filename` | boolean | `false` | Randomize uploaded filenames |
| `slugify_filename` | boolean | `true` | Slugify uploaded filenames |
| `meta` | map | `%{}` | Provider-specific settings |
