defmodule Brando.Pages.PageFragment do
  @moduledoc """
  Ecto schema for the PageFragment schema.
  """

  @type t :: %__MODULE__{}
  @type changeset :: Ecto.Changeset.t()

  use Brando.Web, :schema
  use Brando.Villain.Schema
  use Brando.SoftDelete.Schema
  use Brando.Sequence.Schema

  @required_fields ~w(parent_key key language data creator_id)a
  @optional_fields ~w(html page_id wrapper sequence deleted_at)a
  @derived_fields ~w(
    id
    parent_key
    key
    language
    data
    html
    wrapper
    sequence
    creator_id
    page_id
    inserted_at
    updated_at
    deleted_at
  )a

  @derive {Jason.Encoder, only: @derived_fields}

  schema "pages_fragments" do
    field :parent_key, :string
    field :key, :string
    field :language, :string
    field :wrapper, :string
    villain()
    belongs_to :creator, Brando.Users.User
    belongs_to :page, Brando.Pages.Page
    soft_delete()
    sequenced()
    timestamps()
  end

  @doc """
  Casts and validates `params` against `schema` to create a valid changeset

  ## Example

      schema_changeset = changeset(%__MODULE__{}, :create, params)

  """
  @spec changeset(t, atom, Keyword.t() | Options.t()) :: changeset
  def changeset(schema, action, params \\ %{})

  def changeset(schema, :create, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> guard_for_circular_references()
    |> generate_html()
  end

  def changeset(schema, :update, params) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> guard_for_circular_references()
    |> generate_html()
  end

  @doc """
  Ensure that the fragment doesn't reference itself
  """
  @spec guard_for_circular_references(changeset :: changeset) :: changeset
  def guard_for_circular_references(changeset) do
    case Ecto.Changeset.get_change(changeset, :data) do
      nil ->
        changeset

      change ->
        json = Jason.encode!(change)

        # we need the keys
        key = Ecto.Changeset.get_field(changeset, :key)
        parent_key = Ecto.Changeset.get_field(changeset, :parent_key)
        language = Ecto.Changeset.get_field(changeset, :language)

        # build a fragment ref string
        ref_string = "${FRAGMENT:#{parent_key}/#{key}/#{language}}"

        if String.contains?(json, ref_string) do
          Ecto.Changeset.add_error(
            changeset,
            :data,
            "Fragment contains circular reference to itself, #{ref_string}"
          )
        else
          changeset
        end
    end
  end
end
