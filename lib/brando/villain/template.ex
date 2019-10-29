defmodule Brando.Villain.Template do
  @moduledoc """
  Ecto schema for the Villain Template schema
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :schema

  @required_fields ~w(name namespace help_text class code refs)a
  @optional_fields ~w()a

  @derived_fields ~w(id name namespace help_text class code refs)a
  @derive {Jason.Encoder, only: @derived_fields}

  schema "templates" do
    field :name, :string
    field :namespace, :string
    field :help_text, :string
    field :class, :string
    field :code, :string
    field :refs, {:array, :map}
    timestamps()
  end

  @doc """
  Creates a changeset based on the `schema` and `params`.

  If no params are provided, an invalid changeset is returned
  with no validation performed.
  """
  def changeset(schema, params \\ %{}) do
    schema
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
