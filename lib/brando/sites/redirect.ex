defmodule Brando.Sites.Redirect do
  use Brando.Web, :schema
  use Brando.Schema

  identifier false
  absolute_url false

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
