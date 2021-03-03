defmodule Brando.Villain.Module do
  @moduledoc """
  Ecto schema for the Villain Module schema

  A module can hold a setup for multiple blocks.
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :schema
  use Brando.Schema
  use Brando.Sequence.Schema
  use Brando.SoftDelete.Schema

  meta :en, singular: "module", plural: "modules"
  meta :no, singular: "modul", plural: "moduler"

  identifier false
  absolute_url false

  @required_fields ~w(name namespace help_text class code refs)a
  @optional_fields ~w(sequence deleted_at vars svg multi wrapper)a

  @derived_fields ~w(id name sequence namespace help_text multi wrapper class code refs vars svg deleted_at)a
  @derive {Jason.Encoder, only: @derived_fields}

  schema "pages_modules" do
    field :name, :string
    field :namespace, :string
    field :help_text, :string
    field :class, :string
    field :code, :string
    field :refs, {:array, :map}
    field :vars, :map
    field :svg, :string
    field :multi, :boolean
    field :wrapper, :string

    sequenced()
    timestamps()
    soft_delete()
  end

  @doc """
  Creates a changeset based on the `schema` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(schema, params \\ %{}, _user \\ :system) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
