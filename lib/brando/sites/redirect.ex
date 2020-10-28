defmodule Brando.Sites.Redirect do
  use Brando.Web, :schema

  @fields [:to, :from, :code]

  embedded_schema do
    field :to
    field :from
    field :code
  end

  def changeset(schema, params \\ %{}) do
    schema
    |> cast(params, @fields)
    |> validate_required(@fields)
  end
end
