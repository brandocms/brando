defmodule Brando.MarkdownSources.Delivery do
  @moduledoc false
  use Ecto.Schema
  @schema_prefix "public"

  schema "markdown_webhook_deliveries" do
    field :connection, :string
    field :delivery_id, :string
    field :fingerprint, :string
    field :job_ids, {:array, :integer}, default: []
    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
