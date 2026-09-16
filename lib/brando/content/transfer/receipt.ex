defmodule Brando.Content.Transfer.Receipt do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  @schema_prefix "public"
  schema "content_transfer_receipts" do
    field :package_id, :string
    field :fingerprint, :string
    field :scope, :string
    field :actor_id, :integer
    field :before, :map
    field :after, :map
    field :mappings, :map
    field :refresh, {:array, :map}, default: []
    field :restored_at, :utc_datetime_usec
    timestamps(type: :utc_datetime_usec)
  end
end
