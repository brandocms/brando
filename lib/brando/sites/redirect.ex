defmodule Brando.Sites.Redirect do
  use Brando.Web, :schema
  use Brando.Schema

  meta :en, singular: "redirect", plural: "redirects"
  meta :no, singular: "ompekning", plural: "ompekninger"
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
