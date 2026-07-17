defmodule Brando.Type.VideoConfig do
  @moduledoc """
  Defines a type for a video configuration field.

  ## Upload Strategy

  The `upload_strategy` field determines where videos are uploaded:

  - `:local` (default) - Traditional server upload, files stored on server/CDN
  - `:mux` - Direct upload to Mux for streaming
  - `:cloudflare` - Direct upload to Cloudflare Stream
  - `:s3` - Direct upload to AWS S3
  - `:bunny` - Direct upload to Bunny.net storage

  The `Brando.Videos.Uploader.initiate_upload/3` function automatically routes
  to the appropriate uploader based on this strategy.

  ## Completion callback

  `completed_callback` runs when a local upload is stored or a provider video
  first becomes ready. It accepts an arity-2 function or
  `{module, function, extra_args}`; the video and user are passed before the
  configured arguments. Provider/webhook work may retry, so external side
  effects should be idempotent.

  ## Provider Metadata

  The `meta` field allows you to pass provider-specific settings to video upload
  providers. Each provider has its own namespace.

  ### Structure

      meta: %{
        provider_name: %{
          "setting_name" => value
        }
      }

  ### Mux Provider Settings

  Available settings for Mux uploads via `meta.mux`:

  - `"max_resolution_tier"` - Maximum resolution tier for transcoding
    - `"1080p"` - Transcode up to 1080p (default for cost control)
    - `"2160p"` - Transcode up to 4K
    - Not set - Mux decides based on source

  - `"playback_policy"` - Who can view the video
    - `["public"]` - Anyone with the URL (default)
    - `["signed"]` - Requires signed URLs for playback

  - `"mp4_support"` - Whether to generate MP4 files
    - `"none"` - No MP4 files (default, HLS only)
    - `"standard"` - Generate MP4 files for download

  ### Example Configuration

      asset :video, :video,
        cfg: %{
          upload_strategy: :mux,
          upload_path: Path.join(["videos", "projects"]),
          allowed_mimetypes: ["video/mp4", "video/webm", "video/quicktime"],
          size_limit: 500_000_000,
          meta: %{
            mux: %{
              "max_resolution_tier" => "1080p",
              "playback_policy" => ["public"],
              "mp4_support" => "none"
            }
          }
        }

  ### Priority Order

  Settings are applied in this order (later overrides earlier):
  1. Uploader defaults
  2. `meta` configuration (field-level)
  3. Direct options passed to uploader (runtime overrides)
  """
  use Ecto.Type
  import Brando.Utils, only: [stringy_struct: 2]

  @type upload_strategy :: :bunny | :cloudflare | :local | :mux | :s3
  @type t :: %__MODULE__{
          accept: term(),
          allow_external_urls: boolean(),
          allow_uploads: boolean(),
          allowed_mimetypes: [String.t()],
          cdn: %Brando.CDN.Config{} | nil,
          completed_callback: Brando.Assets.CompletedCallback.t(struct()),
          force_filename: String.t() | nil,
          meta: map(),
          overwrite: boolean(),
          random_filename: boolean(),
          size_limit: pos_integer(),
          slugify_filename: boolean(),
          upload_path: String.t(),
          upload_strategy: upload_strategy()
        }

  @derive Jason.Encoder
  defstruct accept: :any,
            cdn: nil,
            allow_uploads: true,
            allow_external_urls: true,
            allowed_mimetypes: ["video/mp4", "video/webm", "video/ogg", "video/quicktime", "video/x-msvideo"],
            upload_path: Path.join("videos", "default"),
            upload_strategy: :local,
            random_filename: false,
            slugify_filename: true,
            force_filename: nil,
            overwrite: false,
            size_limit: 100_000_000,
            completed_callback: nil,
            meta: %{}

  @doc """
  Returns the internal type representation of our `Role` type for pg
  """
  def type, do: :json

  @doc """
  Cast should return OUR type no matter what the input.
  """

  def cast(val) when is_map(val) do
    {:ok, val}
  end

  @doc """
  Integers are never considered blank
  """
  def blank?(_), do: %Brando.Type.VideoConfig{}

  @doc """
  Load from database. We receive it as a map since Postgrex does the conversion.
  """
  def load(val) when is_map(val) do
    string_struct = stringy_struct(Brando.Type.VideoConfig, val)
    {:ok, string_struct}
  end

  @doc """
  When dumping data to the database we expect a `list`, but check for
  other options as well.
  """
  def dump(val) when is_map(val) do
    {:ok, val}
  end

  def default_config do
    %Brando.Type.VideoConfig{
      size_limit: 100_000_000,
      allowed_mimetypes: ["video/mp4", "video/webm", "video/ogg"],
      random_filename: false,
      allow_uploads: true,
      allow_external_urls: true
    }
  end
end
