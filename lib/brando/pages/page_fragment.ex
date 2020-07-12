defmodule Brando.Pages.PageFragment do
  @moduledoc """
  Ecto schema for the PageFragment schema.
  """

  @type t :: %__MODULE__{}
  @type changeset :: Ecto.Changeset.t()
  @type user :: Brando.Users.User.t() | :system

  use Brando.Web, :schema
  use Brando.Villain.Schema, generate_protocol: false
  use Brando.SoftDelete.Schema
  use Brando.Sequence.Schema

  @required_fields ~w(parent_key key language data creator_id)a
  @optional_fields ~w(html page_id title wrapper sequence deleted_at)a
  @derived_fields ~w(
    id
    title
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
    field :title, :string
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
  @spec changeset(t, map(), user) :: changeset
  def changeset(schema, params \\ %{}, user \\ :system) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> put_creator(user)
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
        ref_string = "${fragment:#{parent_key}/#{key}/#{language}}"

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

  defimpl Phoenix.HTML.Safe, for: Brando.Pages.PageFragment do
    def to_iodata(%{wrapper: nil} = fragment) do
      fragment.html
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end

    def to_iodata(%{wrapper: wrapper} = fragment) do
      wrapper
      |> String.replace("${CONTENT}", fragment.html)
      |> String.replace("${PARENT_KEY}", fragment.parent_key)
      |> String.replace("${KEY}", fragment.key)
      |> String.replace("${LANGUAGE}", fragment.language)
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end
  end
end
