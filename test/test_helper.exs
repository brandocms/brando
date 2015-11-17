ExUnit.start

# Clear tmp dir
File.rm_rf!(Path.join([Mix.Project.app_path, "tmp", "media"]))
File.mkdir_p!(Path.join([Mix.Project.app_path, "tmp", "media"]))

# Basic test repo
alias Brando.Integration.TestRepo, as: Repo

defmodule Brando.Integration.Repo do
  defmacro __using__(opts) do
    quote do
      use Ecto.Repo, unquote(opts)
      def log(cmd) do
        super(cmd)
        on_log = Process.delete(:on_log) || fn -> :ok end
        on_log.()
      end
    end
  end
end

defmodule Brando.Integration.TestRepo do
  use Brando.Integration.Repo, otp_app: :brando
end

defmodule Brando.Integration.Endpoint do
  use Phoenix.Endpoint,
    otp_app: :brando

  plug Plug.Session,
    store: :cookie,
    key: "_test",
    signing_salt: "signingsalt"

  plug Plug.Static,
    at: "/", from: :brando, gzip: false,
    only: ~w(css images js fonts favicon.ico robots.txt),
    cache_control_for_vsn_requests: nil,
    cache_control_for_etags: nil

  socket "/admin/ws", Brando.Integration.UserSocket
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

Code.require_file "support/user_socket.exs", __DIR__
Code.require_file "support/instagram_helper.exs", __DIR__
Code.require_file "support/fixtures.exs", __DIR__
Code.require_file "support/migrations.exs", __DIR__

_   = Ecto.Storage.down(Repo)
:ok = Ecto.Storage.up(Repo)
{:ok, _pid} = Repo.start_link
:ok = Ecto.Migrator.up(Repo, 0, Brando.Integration.Migration, log: false)

Ecto.Adapters.SQL.begin_test_transaction(Brando.Integration.TestRepo)
Brando.endpoint.start_link
