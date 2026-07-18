defmodule Brando.CDN.S3Config do
  @moduledoc """
  Connection settings for the default S3-compatible CDN backend.

  Configure this struct under `Brando.CDN.S3Config` and set a media context's
  CDN `:s3` option to `:default` to reuse it.
  """
  defstruct access_key_id: nil,
            secret_access_key: nil,
            scheme: "https://",
            host: "ams3.digitaloceanspaces.com",
            region: "ams3"
end
