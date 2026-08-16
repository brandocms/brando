defmodule Brando.Tenant.Lock do
  @moduledoc false

  alias Brando.Repo

  @spec with(String.t(), (-> result)) :: result when result: var
  def with(key, fun) when is_binary(key) and is_function(fun, 0) do
    repo = Repo.repo()

    repo.checkout(
      fn ->
        Ecto.Adapters.SQL.query!(
          repo,
          "SELECT pg_advisory_lock(hashtextextended($1, 0))",
          [key]
        )

        try do
          fun.()
        after
          Ecto.Adapters.SQL.query!(
            repo,
            "SELECT pg_advisory_unlock(hashtextextended($1, 0))",
            [key]
          )
        end
      end,
      timeout: :infinity
    )
  end
end
