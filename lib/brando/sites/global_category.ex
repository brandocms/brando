defmodule Brando.GlobalCategory do
  use Brando.Web, :schema

  @fields [:label, :key]

  embedded_schema do
    field :label, :string
    field :key, :string
    embeds_many :globals, Brando.Global, on_replace: :delete
  end

  def changeset(schema, params \\ %{}) do
    schema
    |> cast(params, @fields)
    |> cast_embed(:globals)
    |> validate_required(@fields)
  end
end
