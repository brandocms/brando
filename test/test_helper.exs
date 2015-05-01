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
      require Repo
      import Ecto.Query
      alias Ecto.Integration.TestRepo, as: Repo
    end
  end
end

defmodule Forge do
  use Blacksmith

  @save_one_function &Blacksmith.Config.save/2
  @save_all_function &Blacksmith.Config.save_all/2

  register :user,
    __struct__: Brando.User,
    full_name: "James Williamson",
    email: "james@thestooges.com",
    password: "hunter2hunter2",
    username: "jamesw",
    avatar: nil,
    role: ["2", "4"]
end

defmodule Blacksmith.Config do
  def save(repo, map) do
    repo.insert(map)
  end

  def save_all(repo, list) do
    Enum.map(list, &repo.insert/1)
  end
end

Code.require_file "support/migrations.exs", __DIR__

_   = Ecto.Storage.down(Repo)
:ok = Ecto.Storage.up(Repo)
{:ok, _pid} = Repo.start_link
:ok = Ecto.Migrator.up(Repo, 0, Brando.Integration.Migration, log: false)
Ecto.Adapters.SQL.begin_test_transaction(Brando.Integration.TestRepo)
