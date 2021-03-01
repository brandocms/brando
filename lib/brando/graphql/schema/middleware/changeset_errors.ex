defmodule Brando.GraphQL.Schema.Middleware.ChangesetErrors do
  @behaviour Absinthe.Middleware

  @spec call(Absinthe.Resolution.t(), any()) :: Absinthe.Resolution.t()
  def call(res, _) do
    case res do
      %{errors: [%Ecto.Changeset{} = changeset]} ->
        traversed_errors =
          Ecto.Changeset.traverse_errors(changeset, fn
            {msg, opts} -> String.replace(msg, "%{count}", to_string(opts[:count]))
            msg -> msg
          end)

        errors = [
          [
            message: "Validation failed.",
            code: 422,
            changeset: %{
              errors: traversed_errors,
              action: changeset.action
            }
          ]
        ]

        %{res | errors: errors}

      _ ->
        res
    end
  end
end
