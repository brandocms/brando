defmodule Brando.Sites.Global do
  use Brando.Web, :schema
  use Brando.Schema
  alias Brando.Sites.GlobalCategory

  identifier false
  absolute_url false

  @type t :: %__MODULE__{}
  @type changeset :: Ecto.Changeset.t()

  schema "sites_globals" do
    field :type, :string
    field :label, :string
    field :key, :string
    field :data, :map
    belongs_to :global_category, GlobalCategory
  end

  @required_fields ~w(label key data type)a
  @optional_fields ~w()a

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

  defimpl Phoenix.HTML.Safe, for: Brando.Sites.Global do
    def to_iodata(%{type: "text", data: data}) do
      data
      |> Map.get("value", "")
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end

    def to_iodata(%{type: "boolean", data: data}) do
      data
      |> Map.get("value", false)
      |> to_string()
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end

    def to_iodata(%{type: "html", data: data}) do
      data
      |> Map.get("value", "")
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end

    def to_iodata(%{type: "color", data: data}) do
      data
      |> Map.get("value", "")
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end
  end
end
