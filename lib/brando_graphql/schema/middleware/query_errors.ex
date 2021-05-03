defmodule BrandoGraphQL.Schema.Middleware.QueryErrors do
  @behaviour Absinthe.Middleware

  def call(res, _) do
    case res do
      %{errors: [error_tuple]} when is_tuple(error_tuple) ->
        {schema, error} = error_tuple

        formatted_error =
          "#{schema |> to_string |> String.capitalize()} #{
            error |> to_string |> Phoenix.Naming.humanize() |> String.downcase()
          }"

        %{res | errors: [formatted_error]}

      _ ->
        res
    end
  end
end
