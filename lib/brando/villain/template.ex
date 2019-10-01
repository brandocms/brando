defmodule Brando.Villain.Template do
  @moduledoc """
  Ecto schema for the Villain Template schema
  """

  @type t :: %__MODULE__{}

  use Brando.Web, :schema
  use Brando.Sequence, :schema
  use Brando.SoftDelete.Schema

  @required_fields ~w(name namespace help_text class code refs)a
  @optional_fields ~w(sequence deleted_at)a

  @derived_fields ~w(id name sequence namespace help_text class code refs deleted_at)a
  @derive {Jason.Encoder, only: @derived_fields}

  schema "pages_templates" do
    field :name, :string
    field :namespace, :string
    field :help_text, :string
    field :class, :string
    field :code, :string
    field :refs, {:array, :map}
    sequenced()
    timestamps()
    soft_delete()
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
