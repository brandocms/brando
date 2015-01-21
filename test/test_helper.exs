Logger.configure(level: :info)
ExUnit.start

# Basic test repo
alias Brando.Integration.TestRepo

Application.put_env(:brando, TestRepo,
  url: "ecto://postgres:postgres@localhost/brando_test",
  size: 1,
  max_overflow: 0)

defmodule Brando.Integration.TestRepo do
  use Ecto.Repo,
    otp_app: :brando,
    adapter: Ecto.Adapters.Postgres
end

defmodule Brando.Integration.TestCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import unquote(__MODULE__)
      require TestRepo
      import Ecto.Query
      alias Ecto.Integration.TestRepo
    end
  end

  setup do
    :ok = Ecto.Adapters.Postgres.begin_test_transaction(TestRepo, [])

    on_exit fn ->
      :ok = Ecto.Adapters.Postgres.rollback_test_transaction(TestRepo, [])
    end

    :ok
  end
end

Code.require_file "support/migrations.exs", __DIR__

_   = Ecto.Storage.down(TestRepo)
:ok = Ecto.Storage.up(TestRepo)
{:ok, _pid} = TestRepo.start_link
:ok = Ecto.Migrator.up(TestRepo, 0, Brando.Integration.Migration, log: false)
