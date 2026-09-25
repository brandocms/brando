defmodule Brando.Content.Proposals.Receipt do
  @moduledoc false
  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: false}
  @schema_prefix "public"
  schema "content_proposal_receipts" do
    field :version, :integer
    field :scope, :string
    field :actor_id, :integer
    field :before, :map
    field :after, :map
    field :mappings, :map
    timestamps(type: :utc_datetime_usec)
  end
end
