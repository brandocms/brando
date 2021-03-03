defmodule Brando.Meta do
  use Brando.Web, :schema
  use Brando.Schema

  # :xzibitface:
  meta :en, singular: "meta", plural: "metas"
  meta :no, singular: "meta", plural: "metaer"

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
