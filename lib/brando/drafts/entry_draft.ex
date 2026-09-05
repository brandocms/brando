defmodule Brando.Drafts.EntryDraft do
  @moduledoc "A mutable, user-owned recovery copy. It never publishes or updates the content entry."
  use Ecto.Schema

  @primary_key {:id, Ecto.UUID, autogenerate: false}
  @schema_prefix "public"
  @timestamps_opts [type: :utc_datetime_usec]

  schema "entry_drafts" do
    field :scope, :string
    field :owner_id, :id
    field :entry_type, :string
    field :entry_id, :id
    field :form_name, :string
    field :generation, :integer
    field :base_fingerprint, :string
    field :format_version, :integer, default: 1
    field :schema_version, :integer
    field :payload, :map
    field :checksum, :string
    field :dismissed_at, :utc_datetime_usec
    field :attempted_at, :utc_datetime_usec
    field :resolved_at, :utc_datetime_usec
    field :discarded_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    timestamps()
  end
end
