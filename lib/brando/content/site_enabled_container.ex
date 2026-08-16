defmodule Brando.Content.SiteEnabledContainer do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "public"
  @timestamps_opts [type: :utc_datetime_usec]

  schema "site_enabled_containers" do
    field :site_id, :integer
    field :container_id, :integer
    timestamps()
  end

  def changeset(access \\ %__MODULE__{}, attrs) do
    access
    |> cast(attrs, [:site_id, :container_id])
    |> validate_required([:site_id, :container_id])
    |> unique_constraint([:site_id, :container_id])
  end
end
