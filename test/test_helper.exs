Logger.configure(level: :info)

# Clear tmp dir
File.rm_rf!(Path.join([Mix.Project.app_path(), "tmp", "media"]))
File.mkdir_p!(Path.join([Mix.Project.app_path(), "tmp", "media"]))

{:ok, _} = Application.ensure_all_started(:ex_machina)

ExUnit.start()

defmodule Brando.Integration.Repo do
  use Ecto.Repo,
    otp_app: :brando,
    adapter: Ecto.Adapters.Postgres

  use Brando.SoftDelete.Repo
end

# Basic test repo
alias Brando.Integration.Repo, as: Repo

defmodule Brando.Integration.Endpoint do
  use Phoenix.Endpoint,
    otp_app: :brando

  plug Plug.Session,
    store: :cookie,
    key: "_test",
    signing_salt: "signingsalt"

  plug Plug.Static,
    at: "/",
    from: :brando,
    gzip: false,
    only: ~w(css images js fonts favicon.ico robots.txt),
    cache_control_for_vsn_requests: nil,
    cache_control_for_etags: nil
end

defmodule Brando.Integration.TestCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      require Repo
      import Ecto.Query
      alias Ecto.Integration.Repo, as: Repo
    end
  end
end

Mix.Task.run("ecto.drop", ["-r", Repo, "--quiet"])
Mix.Task.run("ecto.create", ["-r", Repo, "--quiet"])
Mix.Task.run("ecto.migrate", ["-r", Repo, "--quiet"])
Repo.start_link()
Mix.Task.run("ecto.seed", ["-r", Repo, "--quiet"])

Brando.Cache.Identity.set()
Brando.Cache.Globals.set()

Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
Brando.endpoint().start_link
Brando.Registry.start_link()
Brando.Registry.register(Brando, [:gettext])
