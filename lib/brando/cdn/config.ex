defmodule Brando.CDN.Config do
  @moduledoc """
  CDN settings for a media context or field config.

  Set as the `:cdn` key of `Brando.Files`, `Brando.Images`, `Brando.Static`
  (see `Brando.CDN` for examples), or of an individual field config such as
  `Brando.Type.VideoConfig`.

  ## Options

    * `:enabled` — upload to the CDN at all. Defaults to `false`, which keeps
      everything on local storage.
    * `:direct` — opt into direct browser-to-bucket uploads via presigned URLs
      for files and videos. See `Brando.Uploads`. Defaults to `false`.
    * `:direct_acl` — object ACL header sent with direct uploads, for buckets
      that require one. Leave `nil` (the default) and use a bucket policy or
      Object Ownership on modern AWS buckets.
    * `:media_url` — public base URL the stored objects are served from.
    * `:bucket` — bucket name to upload to.
    * `:keep_local_copy` — keep the local file after a server-side upload to
      the CDN. Defaults to `true`. Direct uploads never produce a local copy,
      regardless of this setting.
    * `:s3` — a `Brando.CDN.S3Config` with the connection settings, or the
      atom `:default` to reuse the config set under `Brando.CDN.S3Config`.
  """
  defstruct enabled: false,
            direct: false,
            direct_acl: nil,
            media_url: nil,
            bucket: nil,
            keep_local_copy: true,
            s3: %Brando.CDN.S3Config{}
end
