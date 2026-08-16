defmodule Brando.Content.SiteEnabledModule do
  @moduledoc false

  use Ecto.Schema
  import Ecto.Changeset

  @schema_prefix "public"
  @timestamps_opts [type: :utc_datetime_usec]

  schema "site_enabled_modules" do
    field :site_id, :integer
    field :module_id, :integer
    timestamps()
  end

  def changeset(access \\ %__MODULE__{}, attrs) do
    access
    |> cast(attrs, [:site_id, :module_id])
    |> validate_required([:site_id, :module_id])
    |> unique_constraint([:site_id, :module_id])
  end
end
