defmodule Brando.Navigation.Item do
  @moduledoc """
  Ecto schema for the Menu schema.
  """

  use Brando.Web, :schema
  use Brando.Schema

  @type t :: %__MODULE__{}
  @type user :: Brando.Users.User.t() | :system

  meta :en, singular: "menu item", plural: "menu items"
  meta :no, singular: "menypunkt", plural: "menypunkter"

  identifier fn entry -> "#{entry.title}" end
  absolute_url false

  embedded_schema do
    field :status, Brando.Type.Status
    field :title, :string
    field :key, :string
    field :url, :string
    field :open_in_new_window, :boolean, default: false
    embeds_many :items, __MODULE__, on_replace: :delete
  end

  @required_fields ~w(status title key url open_in_new_window)a
  @optional_fields ~w()a

  @doc """
  Casts and validates `params` against `schema` to create a valid changeset

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, Keyword.t() | Options.t()) :: Ecto.Changeset.t()
  def changeset(schema, params \\ %{}) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> cast_embed(:items)
    |> validate_required(@required_fields)
  end
end
