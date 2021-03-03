defmodule Brando.ConfigEntry do
  use Brando.Web, :schema
  use Brando.Schema

  meta :en, singular: "config entry", plural: "config entries"
  meta :no, singular: "konfigurasjonspunkt", plural: "konfigurasjonspunkter"
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
