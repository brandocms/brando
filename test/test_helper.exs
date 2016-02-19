Logger.configure(level: :info)
ExUnit.start

# Clear tmp dir
File.rm_rf!(Path.join([Mix.Project.app_path, "tmp", "media"]))
File.mkdir_p!(Path.join([Mix.Project.app_path, "tmp", "media"]))

# Basic test repo
alias Brando.Integration.TestRepo, as: Repo

defmodule Brando.Integration.TestRepo do
  use Ecto.Repo, otp_app: :brando
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

_ = Ecto.Storage.down(Repo)
_ = Ecto.Storage.up(Repo)

Mix.Task.run "ecto.create", ["-r", Repo, "--quiet"]
Mix.Task.run "ecto.migrate", ["-r", Repo, "--quiet"]

Repo.start_link

Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
# Ecto.Adapters.SQL.begin_test_transaction(Brando.Integration.TestRepo)
Brando.endpoint.start_link
