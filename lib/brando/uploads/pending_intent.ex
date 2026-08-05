defmodule Brando.Uploads.PendingIntent do
  @moduledoc """
  A client-direct upload the server has authorized but not yet finalized.

  Client-direct transports (files/videos → S3/Spaces) hand the browser a
  presigned PUT and expect a `direct_complete` back. Everything needed to turn
  that callback into an asset row — the object key and the resolved config
  target — used to live only in the sticky `BrandoAdmin.UploadManager`'s
  `items` assign. `mount/1` hard-assigns `items: %{}`, so a manager that
  remounted mid-transfer (reconnect, or navigation that rebuilt the Chrome)
  answered the completion with a silent no-op: bytes in the bucket, no `File`
  or `Image` row, nothing to reap.

  The key and target are recorded here at *initiate* time and are the only ones
  finalize will trust — a `direct_complete` never supplies its own, before or
  after a remount. Rows are removed on finalize, on client-reported error, and
  on cancel; whatever is left is an abandoned transfer and belongs to
  `Brando.Worker.UploadIntentReaper`.

  Deliberately not a Blueprint: this is transport bookkeeping with a lifetime
  measured in minutes, not content. It has no admin listing, no identifier and
  no soft delete — a reaped intent must actually leave the table, or the reaper
  would keep finding it.
  """
  use Ecto.Schema

  @timestamps_opts [type: :utc_datetime_usec]

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  @asset_types [:image, :file, :video]

  @required [:ref, :key, :resolved_target, :asset_type]
  @optional [:mime_type, :filename, :filesize, :target, :creator_id]

  schema "uploads_pending_intents" do
    field :ref, Ecto.UUID
    field :key, :string
    field :resolved_target, :string
    field :asset_type, Ecto.Enum, values: @asset_types
    field :mime_type, :string
    field :filename, :string
    field :filesize, :integer

    # The normalized `Brando.Uploads.AssetIntent` target: deliver_topic, kind,
    # field, path, folder_id. Kept whole so a finalize after a remount can
    # deliver exactly like an in-process one.
    field :target, :map, default: %{}

    belongs_to :creator, Brando.Users.User

    timestamps()
  end

  def changeset(intent \\ %__MODULE__{}, attrs) do
    intent
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> unique_constraint(:ref)
  end

  def asset_types, do: @asset_types
end
