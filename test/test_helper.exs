#Logger.configure(level: :info)
ExUnit.start

# Clear tmp dir
File.rm_rf!(Path.join([Mix.Project.app_path, "tmp", "media"]))
File.mkdir_p!(Path.join([Mix.Project.app_path, "tmp", "media"]))

# Basic test repo
alias Brando.Integration.TestRepo

defmodule Brando.Integration.TestRepo do
  use Ecto.Repo,
    otp_app: :brando
end

defmodule Brando.Integration.Endpoint do
  use Phoenix.Endpoint,
    otp_app: :brando
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
    :ok = Ecto.Adapters.SQL.begin_test_transaction(TestRepo, [])

    on_exit fn ->
      :ok = Ecto.Adapters.SQL.rollback_test_transaction(TestRepo, [])
    end

    :ok
  end
end

Code.require_file "support/migrations.exs", __DIR__

_   = Ecto.Storage.down(TestRepo)
:ok = Ecto.Storage.up(TestRepo)
{:ok, _pid} = TestRepo.start_link
:ok = Ecto.Migrator.up(TestRepo, 0, Brando.Integration.Migration, log: false)
