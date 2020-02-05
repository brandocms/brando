defmodule Brando.Global do
  use Brando.Web, :schema

  @fields [:label, :key, :value]

  embedded_schema do
    field :label
    field :key
    field :value
  end

  def changeset(schema, params \\ %{}) do
    schema
    |> cast(params, @fields)
    |> validate_required(@fields)
  end

  defimpl Phoenix.HTML.Safe, for: Brando.Global do
    def to_iodata(link) do
      link.value
      |> Phoenix.HTML.raw()
      |> Phoenix.HTML.Safe.to_iodata()
    end
  end
end
