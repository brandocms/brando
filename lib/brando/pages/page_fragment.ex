defmodule Brando.Pages.PageFragment do
  @moduledoc """
  Ecto schema for the PageFragment schema.
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :schema
  use Brando.Villain.Schema

  @required_fields ~w(parent_key key language data creator_id)a
  @optional_fields ~w(html page_id)a
  @derived_fields ~w(
    id
    parent_key
    key
    language
    data
    html
    creator_id
    page_id
  )a

  @derive {Jason.Encoder, only: @derived_fields}

  schema "pagefragments" do
    field :parent_key, :string
    field :key, :string
    field :language, :string
    villain()
    belongs_to :creator, Brando.User
    belongs_to :page, Brando.Pages.Page

    timestamps()
  end

  @doc """
  Casts and validates `params` against `schema` to create a valid changeset

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, atom, Keyword.t() | Options.t()) :: Ecto.Changeset.t()
  def changeset(schema, action, params \\ %{})

  def changeset(schema, :create, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> generate_html()
  end

  def changeset(schema, :update, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> generate_html()
  end

  def encode_data(params) do
    if is_list(params.data) do
      Map.put(params, :data, Jason.encode!(params.data))
    else
      params
    end
  end
end
