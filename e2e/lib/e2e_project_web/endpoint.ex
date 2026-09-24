defmodule E2eProjectWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :e2e_project

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_e2e_project_key",
    signing_salt: "flX6/aG5"
  ]

  if Application.compile_env(:e2e_project, :sql_sandbox) do
    # Rows a test writes are rolled back with its sandbox, but pages and 404
    # lookups rendered from them stay in Brando's query caches for 15 minutes,
    # so the next test (or a retry of the same one) is served content that no
    # longer exists. Both caches only memoize database reads, so emptying them
    # when a test checks out its sandbox is always safe.
    plug :clear_query_caches_on_checkout

    # The Playwright fixture checks each test's sandbox back in at teardown
    # (test-support/setupAuth.js), so this timeout is only a backstop for a
    # leaked sandbox. It must outlast the longest `test.setTimeout` (240s):
    # once it fires, every query the test's LiveViews make fails, and a slow
    # test dies on its database instead of finishing within its own budget.
    plug Phoenix.Ecto.SQL.Sandbox,
      at: "/sandbox",
      repo: E2eProject.Repo,
      timeout: 300_000
  end

  socket "/admin/socket", BrandoAdmin.AdminSocket,
    websocket: [connect_info: [:user_agent]],
    longpoll: true

  socket "/live",
         Phoenix.LiveView.Socket,
         websocket: [connect_info: [:user_agent, session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phoenix.digest
  # when deploying your static files in production.
  plug Brando.Plug.SiteAssets

  plug Plug.Static,
    at: "/",
    from: :e2e_project,
    gzip: Brando.env() == :prod,
    only: ~w(assets js fonts images ico favicon.ico),
    cache_control_for_etags: (Brando.env() == :prod && "public, max-age=31536000") || false,
    cache_control_for_vsn_requests: (Brando.env() == :prod && "public, max-age=31536000") || false

  plug Brando.Plug.Media, at: "/media"

  if Code.ensure_loaded?(Tidewave) do
    plug Tidewave
  end

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :e2e_project
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug BrandoWeb.Plugs.GitHubMarkdownWebhook,
    allow_insecure: Application.compile_env(:e2e_project, :sql_sandbox, false)

  plug Plug.Parsers,
    parsers: [:urlencoded, {:multipart, length: 100_000_000}, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug Brando.Plug.LivePreview
  plug E2eProjectWeb.Router

  if Application.compile_env(:e2e_project, :sql_sandbox) do
    defp clear_query_caches_on_checkout(
           %Plug.Conn{method: "POST", path_info: ["sandbox"]} = conn,
           _opts
         ) do
      Cachex.clear(:query)
      Cachex.clear(:four_oh_four)
      conn
    end

    defp clear_query_caches_on_checkout(conn, _opts), do: conn
  end
end
