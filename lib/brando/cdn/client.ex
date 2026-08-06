defmodule Brando.CDN.Client do
  @moduledoc """
  The seam between Brando and the S3-compatible object store.

  Everything Brando needs from a bucket at *runtime* goes through here, so a
  test can drive the direct-upload path — presign, verify the object landed,
  finalize, reap — without a bucket. Before this boundary existed there was no
  way to test a successful `Brando.Uploads.finalize_direct/3` at all, which is
  recorded as the honest limit of the D1 work in the form audit's Phase 2.

  Deliberately scoped to the calls that actually cross the network in a request
  or job path. Three things are outside it on purpose:

    * **Presigning is not a network call.** `ExAws.S3.presigned_url/5` is an HMAC
      over local credentials, so routing it through a mock would buy nothing and
      cost the four existing `presign_put/3` tests their real assertions — they
      check the signed URL's query parameters, which only a real signature has.
    * The bulk operations (`upload_file/3`, `upload_image/4`,
      `ensure_bucket_exists/1`) move real bytes; a stub proves nothing about them
      and would hide the integration failures that are the interesting ones.
    * The `mix brando.*` tasks are operator tools, run against a real bucket.

  ## Why a behaviour here and `Req.Test` for the video providers

  The Mux/Bunny/Cloudflare clients speak HTTP through `Req`, which ships its own
  test transport (`Req.Test`). Wrapping them in a behaviour would be inventing a
  seam the library already provides, and a behaviour mock cannot assert what
  those clients actually get wrong — the request they build. They are stubbed at
  the transport instead; see `Brando.Videos.Uploaders.Mux.req_options/0`.

  ExAws has no equivalent, and these calls are semantic rather than
  request-shaped, so they get a behaviour.

  ## Configuration

      config :brando, :cdn_client, Brando.CDN.Client.Mock

  Defaults to `Brando.CDN.Client.ExAws`.
  """

  @typedoc "An `ExAws` keyword-list config, as built by `Brando.CDN.get_s3_config/2`"
  @type s3_config :: keyword

  @doc "Fetch object metadata. `{:error, :not_found}` when the key is absent."
  @callback head_object(bucket :: binary, key :: binary, s3_config) ::
              {:ok, map} | {:error, term}

  @doc "Delete an object. S3 DELETE is idempotent, so a missing key succeeds."
  @callback delete_object(bucket :: binary, key :: binary, s3_config) ::
              {:ok, map} | {:error, term}

  @doc """
  The configured implementation.

  Read per call rather than at compile time so a test can swap it without a
  recompile, and so an application can point at its own client.
  """
  def impl, do: Application.get_env(:brando, :cdn_client, Brando.CDN.Client.ExAws)
end

defmodule Brando.CDN.Client.ExAws do
  @moduledoc """
  The real `Brando.CDN.Client` — a thin pass-through to `ExAws`.

  Thin on purpose: anything with logic in it would be logic no test exercises,
  since this is the module that gets swapped out.
  """
  @behaviour Brando.CDN.Client

  @impl true
  def head_object(bucket, key, s3_config) do
    bucket
    |> ExAws.S3.head_object(key)
    |> ExAws.request(s3_config)
  end

  @impl true
  def delete_object(bucket, key, s3_config) do
    bucket
    |> ExAws.S3.delete_object(key)
    |> ExAws.request(s3_config)
  end
end
