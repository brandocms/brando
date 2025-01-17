defmodule Brando.Query.Helpers do
  @moduledoc false
  @doc """
  Check if `field` on `schema` contains `data`

      from q in query, where: jsonb_contains(q, :colors, [%{hex_value: color}])
  """
  defmacro jsonb_contains(schema, field, data) do
    require Ecto.Query

    quote do
      fragment("?::jsonb @> ?::jsonb", field(unquote(schema), ^unquote(field)), ^unquote(data))
    end
  end
end
