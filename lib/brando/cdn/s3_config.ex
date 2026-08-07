defmodule Brando.CDN.S3Config do
  @moduledoc """
  Connection settings for the default S3-compatible CDN backend.

  Configure this struct under `Brando.CDN.S3Config` and set a media context's
  CDN `:s3` option to `:default` to reuse it.

  The credential fields are redacted from `inspect/1`, because this struct is
  reachable from `%Brando.CDN.Config{}` and therefore from anything that
  inspects a media config — a crash report, a Logger line, an error tracker.
  Note that `Brando.CDN.get_s3_config/2` with `as: :keyword_list` returns a
  plain keyword list built with `Map.from_struct/1`, which this derivation does
  **not** cover; callers that interpolate that list are responsible for
  dropping the credentials themselves.
  """
  @derive {Inspect, except: [:access_key_id, :secret_access_key]}
  defstruct access_key_id: nil,
            secret_access_key: nil,
            scheme: "https://",
            host: "ams3.digitaloceanspaces.com",
            region: "ams3"
end
