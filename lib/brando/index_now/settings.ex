defmodule Brando.IndexNow.Settings do
  @moduledoc """
  A site environment's IndexNow settings (`Brando.IndexNow`): whether it
  submits, its key, and the last submission and the answer to it. One row,
  created the first time IndexNow is turned on.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @type t :: %__MODULE__{}

  schema "sites_indexnow" do
    field :enabled, :boolean, default: false
    field :key, :string
    field :last_submitted_at, :utc_datetime
    field :last_status, :integer
    field :last_response, :string
    field :last_url_count, :integer
    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(settings, attrs) do
    settings
    |> cast(attrs, [:enabled, :key, :last_submitted_at, :last_status, :last_response, :last_url_count])
    |> validate_required([:key])
    |> validate_format(:key, ~r/^[a-f0-9]{32}$/)
  end
end
