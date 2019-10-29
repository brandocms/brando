defmodule <%= application_module %>Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :<%= application_name %>

  # wallaby testing env
  if Application.get_env(:<%= application_name %>, :sql_sandbox) do
    plug Phoenix.Ecto.SQL.Sandbox
  end

  socket "/admin/socket", <%= application_module %>Web.AdminSocket,
    websocket: true,
    longpoll: true

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phoenix.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/", from: :<%= application_name %>, gzip: false,
    only: ~w(css fonts img images js ico favicon.ico robots.txt)

  plug Plug.Static,
    at: "/media", from: Brando.config(:media_path),
    cache_control_for_etags: "public, max-age=31536000",
    cache_control_for_vsn_requests: "public, max-age=31536000"

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Plug.RequestId
  plug Plug.Logger

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json, Absinthe.Plug.Parser],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  plug Plug.Session,
    store: :cookie,
    key: "_<%= application_name %>_key",
    signing_salt: "Wq19EWJ9"

  plug <%= application_module %>Web.Router
end
