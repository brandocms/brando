Logger.configure(level: :info)
ExUnit.start

# Clear tmp dir
File.rm_rf!(Path.join([Mix.Project.app_path, "tmp", "media"]))
File.mkdir_p!(Path.join([Mix.Project.app_path, "tmp", "media"]))

# Basic test repo
alias Brando.Integration.TestRepo

Application.put_env(:brando, TestRepo,
  url: "ecto://postgres:postgres@localhost/brando_test",
  size: 1,
  max_overflow: 0)

Application.put_env(:brando, Brando.Menu, [
  modules: [Brando.Admin, Brando.Users],
  colors: ["#FBA026;", "#F87117;", "#CF3510;", "#890606;", "#FF1B79;",
           "#520E24;", "#8F2041;", "#DC554F;", "#FF905E;", "#FAC51C;",
           "#D6145F;", "#AA0D43;", "#7A0623;", "#430202;", "#500422;",
           "#870B46;", "#D0201A;", "#FF641A;"]])
Application.put_env(:brando, :router, RouterHelper.TestRouter)
Application.put_env(:brando, :repo, Brando.Integration.TestRepo)

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
