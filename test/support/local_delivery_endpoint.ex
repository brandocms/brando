defmodule Brando.Test.LocalDeliveryController do
  @moduledoc false
  # A site's dynamic pages: every path answers, naming the environment that
  # answered it, so a test sees when a request reached Phoenix, but a path
  # under one of Brando's own prefixes (`/__…`), which no page has: that one
  # goes to the fallback controller, as a generated page controller's would
  use Phoenix.Controller, formats: [:html]

  action_fallback BrandoWeb.FallbackController

  def show(%Plug.Conn{path_info: ["__" <> _prefix | _rest]}, _params), do: {:error, {:page, :not_found}}
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
  Markdown, IndexNow and health plugs, and a router with `Brando.Plug.Tenant`.

  `start/0` starts it under the test's supervisor.
  """

  use Phoenix.Endpoint, otp_app: :brando

  @doc "Starts the endpoint under the test's supervisor."
  def start, do: start(__MODULE__)

  @doc "Starts `endpoint` under the test's supervisor, with `host` in its URL."
  def start(endpoint, host \\ "endpoint.test") do
    previous = Application.fetch_env(:brando, endpoint)

    Application.put_env(:brando, endpoint,
      url: [host: host],
      server: false,
      secret_key_base: String.duplicate("local-delivery", 6),
      live_view: [signing_salt: "localdeliverysalt"],
      pubsub_server: BrandoIntegration.PubSub
    )

    ExUnit.Callbacks.on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:brando, endpoint, value)
        :error -> Application.delete_env(:brando, endpoint)
      end
    end)

    ExUnit.Callbacks.start_supervised!(endpoint)
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
  plug Brando.Plug.Health
  plug Brando.Test.LocalDeliveryRouter
end

defmodule Brando.Test.LocalDeliveryNarrowEndpoint do
  @moduledoc """
  `Brando.Test.LocalDeliveryEndpoint` with a `Plug.Static` that serves only
  `css/`, narrower than the web module's `static_paths/0` may say, and
  without `Brando.Plug.Health`.
  """

  use Phoenix.Endpoint, otp_app: :brando

  @doc "Starts the endpoint under the test's supervisor."
  def start, do: Brando.Test.LocalDeliveryEndpoint.start(__MODULE__)

  plug Brando.Plug.SiteAssets

  plug Plug.Static,
    at: "/",
    from: {Brando.Assets.SiteAssets.Capture, :release_root, []},
    gzip: false,
    only: ~w(css)

  plug Plug.Session, store: :cookie, key: "_local_delivery", signing_salt: "localdelivery"
  plug Brando.Test.LocalDeliveryRouter
end

defmodule Brando.Test.LocalDeliveryWeb do
  @moduledoc false
  # A web module whose `static_paths/0` the tests set
  def static_paths, do: Application.get_env(:brando, __MODULE__, ~w(assets css js))
end
