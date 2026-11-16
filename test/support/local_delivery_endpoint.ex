defmodule Brando.Test.LocalDeliveryController do
  @moduledoc false
  # A site's dynamic pages: every path answers, naming the environment that
  # answered it, so a test sees when a request reached Phoenix
  use Phoenix.Controller, formats: [:html]

  def show(conn, _params), do: Plug.Conn.send_resp(conn, 200, "dynamic #{conn.request_path} in #{environment(conn)}")
  def create(conn, _params), do: Plug.Conn.send_resp(conn, 200, "posted #{conn.request_path} in #{environment(conn)}")

  defp environment(conn), do: conn.assigns[:current_environment] && conn.assigns.current_environment.key
end

defmodule Brando.Test.LocalDeliveryRouter do
  @moduledoc false
  # The admin, then a site's pipeline with `Brando.Plug.Tenant`, Brando's
  # page routes and a catch-all, in the order an installation generates them
  use Phoenix.Router

  import Brando.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :assign_language
    plug Brando.Plug.Tenant
  end

  admin_routes do
    live "/projects", BrandoIntegrationWeb.Projects.ProjectListLive
  end

  scope "/" do
    pipe_through :browser
    page_routes(catch_all: false)
    post "/*path", Brando.Test.LocalDeliveryController, :create
    get "/*path", Brando.Test.LocalDeliveryController, :show
  end

  def assign_language(conn, _opts), do: Plug.Conn.assign(conn, :language, "en")
end

defmodule Brando.Test.LocalDeliveryEndpoint do
  @moduledoc """
  An installation's endpoint, in the order its plugs run there: the site's
  asset sets and the release's static files (the release root,
  `config :brando, :release_static_path`), the session, the preview,
  Markdown and IndexNow plugs, and a router with `Brando.Plug.Tenant`.

  `start/0` starts it under the test's supervisor.
  """

  use Phoenix.Endpoint, otp_app: :brando

  @doc "Starts the endpoint under the test's supervisor."
  def start do
    previous = Application.fetch_env(:brando, __MODULE__)

    Application.put_env(:brando, __MODULE__,
      url: [host: "endpoint.test"],
      server: false,
      secret_key_base: String.duplicate("local-delivery", 6),
      live_view: [signing_salt: "localdeliverysalt"],
      pubsub_server: BrandoIntegration.PubSub
    )

    ExUnit.Callbacks.on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:brando, __MODULE__, value)
        :error -> Application.delete_env(:brando, __MODULE__)
      end
    end)

    ExUnit.Callbacks.start_supervised!(__MODULE__)
    :ok
  end

  plug Brando.Plug.SiteAssets

  plug Plug.Static,
    at: "/",
    from: {Brando.Assets.SiteAssets.Capture, :release_root, []},
    gzip: false,
    only: ~w(assets css js fonts images favicon.ico)

  plug Plug.Parsers, parsers: [:urlencoded], pass: ["*/*"]
  plug Plug.Session, store: :cookie, key: "_local_delivery", signing_salt: "localdelivery"
  plug Brando.Plug.LivePreview
  plug Brando.Plug.Markdown
  plug Brando.Plug.IndexNow
  plug Brando.Test.LocalDeliveryRouter
end
