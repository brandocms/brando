defmodule Brando.ConfigEntry do
  use Brando.Web, :schema
  use Brando.Schema

  identifier false
  absolute_url false

  @fields [:key, :value]

  embedded_schema do
    field :key
    field :value
  end

  def changeset(schema, params \\ %{}) do
    schema
    |> cast(params, @fields)
    |> validate_required(@fields)
  end
end
