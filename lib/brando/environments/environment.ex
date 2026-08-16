defmodule Brando.Environments.Environment do
  @moduledoc """
  A named content environment in Brando's public tenant registry.

  This record describes an environment; creation and migration of its
  PostgreSQL content schema belongs to the environment phase. Only one record
  per site may be marked live, enforced by a partial unique database index.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Brando.Sites.Site

  @schema_prefix "public"
  @timestamps_opts [type: :utc_datetime_usec]
  @key_format ~r/^[a-z0-9]+(?:-[a-z0-9]+)*$/

  @type t :: %__MODULE__{}

  schema "environments" do
    field :name, :string
    field :key, :string
    field :live, :boolean, default: false
    field :domain, :string

    belongs_to :site, Site

    timestamps()
  end

  @required_fields [:site_id, :name, :key, :live]
  @optional_fields [:domain]

  def changeset(environment \\ %__MODULE__{}, attrs) do
    environment
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> normalize_domain()
    |> validate_required(@required_fields)
    |> validate_length(:name, min: 1)
    |> validate_format(:key, @key_format)
    |> foreign_key_constraint(:site_id)
    |> unique_constraint([:site_id, :key])
    |> unique_constraint(:domain)
    |> unique_constraint(:live, name: :environments_one_live_per_site_index)
  end

  defp normalize_domain(changeset) do
    update_change(changeset, :domain, fn
      domain when is_binary(domain) ->
        case domain |> String.trim() |> String.downcase() do
          "" -> nil
          normalized -> normalized
        end

      domain ->
        domain
    end)
  end
end
