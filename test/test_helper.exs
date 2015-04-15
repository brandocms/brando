#Logger.configure(level: :info)
ExUnit.start

# Clear tmp dir
File.rm_rf!(Path.join([Mix.Project.app_path, "tmp", "media"]))
File.mkdir_p!(Path.join([Mix.Project.app_path, "tmp", "media"]))

# Basic test repo
alias Brando.Integration.TestRepo, as: Repo

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
      require Repo
      import Ecto.Query
      alias Ecto.Integration.TestRepo, as: Repo
    end
  end

  setup do
    :ok = Ecto.Adapters.SQL.begin_test_transaction(Repo, [])

    on_exit fn ->
      :ok = Ecto.Adapters.SQL.rollback_test_transaction(Repo, [])
    end

    :ok
  end
end

Code.require_file "support/migrations.exs", __DIR__

_   = Ecto.Storage.down(Repo)
:ok = Ecto.Storage.up(Repo)
{:ok, _pid} = Repo.start_link
:ok = Ecto.Migrator.up(Repo, 0, Brando.Integration.Migration, log: false)
