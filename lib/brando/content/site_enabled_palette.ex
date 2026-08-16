defmodule Brando.Content.SiteEnabledPalette do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "public"
  @timestamps_opts [type: :utc_datetime_usec]

  schema "site_enabled_palettes" do
    field :site_id, :integer
    field :palette_id, :integer
    timestamps()
  end

  def changeset(access \\ %__MODULE__{}, attrs) do
    access
    |> cast(attrs, [:site_id, :palette_id])
    |> validate_required([:site_id, :palette_id])
    |> unique_constraint([:site_id, :palette_id])
  end
end
