defmodule Brando.Schema.Middleware.ChangesetErrors do
  @behaviour Absinthe.Middleware

  @spec call(Absinthe.Resolution.t(), any()) :: Absinthe.Resolution.t()
  def call(res, _) do
    with %{errors: [%Ecto.Changeset{} = changeset]} <- res do
      errors = [
        [
          message: "Validation failed.",
          code: 422,
          changeset: %{
            errors:
              changeset
              |> Ecto.Changeset.traverse_errors(fn
                {msg, opts} -> String.replace(msg, "%{count}", to_string(opts[:count]))
                msg -> msg
              end),
            action: changeset.action
          }
        ]
      ]

      %{res | errors: errors}
    else
      _ -> res
    end
  end
end
