alias BrandoIntegration.Repo, as: Repo

:erlang.system_flag(:backtrace_depth, 30)

# Clear tmp dir
File.rm_rf!(Path.join([Mix.Project.app_path(), "tmp", "media"]))
File.mkdir_p!(Path.join([Mix.Project.app_path(), "tmp", "media"]))

BrandoIntegration.Repo.start_link()

{:ok, _} = Application.ensure_all_started(:ex_machina)

Supervisor.start_link(
  [{Phoenix.PubSub, name: BrandoIntegration.PubSub, pool_size: 1}, Brando],
  strategy: :one_for_one
)

defmodule BrandoIntegration.Presence do
  @moduledoc false
  use BrandoAdmin.Presence,
    otp_app: :brando,
    pubsub_server: BrandoIntegration.PubSub,
    presence: __MODULE__
end

defmodule BrandoIntegrationWeb.Gettext do
  @moduledoc false
  use Gettext.Backend, otp_app: :brando, priv: "priv/gettext/frontend"
end

defmodule BrandoIntegrationAdmin.Gettext do
  @moduledoc false
  use Gettext.Backend, otp_app: :brando, priv: "priv/gettext/backend"
end

defmodule BrandoIntegrationWeb.Villain.Filters do
  @moduledoc false
  use Brando.Villain.Filters
end

defmodule Brando.Villain.ParserTest.Parser do
  @moduledoc false
  use Brando.Villain.Parser
end

# Basic test repo
defmodule BrandoIntegrationWeb.Endpoint do
  use Phoenix.Endpoint,
    otp_app: :brando

  socket "/admin/socket", BrandoIntegration.AdminSocket,
    websocket: true,
    longpoll: false

  plug Plug.Session,
    store: :cookie,
    key: "_test",
    signing_salt: "signingsalt"

  plug Brando.Plug.LivePreview

  plug Plug.Static,
    at: "/",
    from: :brando,
    gzip: false,
    only: ~w(css images js fonts favicon.ico robots.txt),
    cache_control_for_vsn_requests: nil,
    cache_control_for_etags: nil
end

defmodule BrandoIntegration.Authorization do
  @moduledoc false
  use Brando.Authorization

  types([{"User", Brando.Users.User}])

  # Rules for :superuser
  rules :superuser do
    can :manage, :all
  end
end

defmodule BrandoIntegration.AdminSocket do
  @moduledoc """
  Socket specs for System and Stats channels.
  """
  use Phoenix.Socket

  ## Channels
  channel "user:*", Brando.UserChannel
  channel "live_preview:*", Brando.LivePreviewChannel

  @doc """
  Connect socket with token
  """
  @impl true
  def connect(%{"token" => _jwt}, socket) do
    {:ok, socket}
  end

  def connect(_params, _socket) do
    # if we get here, we did not authenticate
    :error
  end

  # Socket id's are topics that allow you to identify all sockets for a given user:
  #
  #     def id(socket), do: "users_socket:#{socket.assigns.user_id}"
  #
  # Would allow you to broadcast a "disconnect" event and terminate
  # all active sockets and channels for a given user:
  #
  #     AlexArkWeb.Endpoint.broadcast("users_socket:#{user.id}", "disconnect", %{})
  #
  # Returning `nil` makes this socket anonymous.
  @impl true
  def id(_socket), do: nil
end

defmodule BrandoIntegration.Processor.Commands do
  @moduledoc false
  def command(_, _, _), do: {:ok, 0}
end

defmodule BrandoIntegrationWeb.PageHTML do
  use Phoenix.Component

  embed_templates "fixtures/templates/page_html/*"
end

defmodule BrandoIntegrationWeb.Layouts do
  @moduledoc false
  use Phoenix.Component

  def app(assigns) do
    ~H"""
    <html>
      <head></head>
      <body>
        {@inner_content}
      </body>
    </html>
    """
  end
end

defmodule BrandoIntegrationWeb.LivePreview do
  @moduledoc false
  use Brando.LivePreview

  preview_target Brando.Pages.Page do
    template fn e -> {BrandoIntegrationWeb.PageHTML, "#{e.key}.html"} end
    layout {BrandoIntegrationWeb.Layouts, "app"}
    template_section fn entry -> entry.key end

    assign :restaurants, fn _ -> __MODULE__.list_restaurants!() end
    assign :employees, fn _ -> __MODULE__.list_employees!() end
  end

  def list_restaurants! do
    [
      %{id: 1, name: "Oslo"},
      %{id: 2, name: "Bergen"}
    ]
  end

  def list_employees! do
    [
      %{id: 1, name: "Todd"},
      %{id: 2, name: "Rod"}
    ]
  end
end

defmodule CompileTimeAssertions do
  @moduledoc false
  defmodule DidNotRaise, do: defstruct(message: nil)

  defmacro assert_compile_time_raise(expected_exception, expected_message, fun) do
    actual_exception =
      try do
        Code.eval_quoted(fun)
        %DidNotRaise{}
      rescue
        e -> e
      end

    quote do
      assert unquote(actual_exception.__struct__) == unquote(expected_exception)
      assert unquote(actual_exception.message) =~ unquote(expected_message)
    end
  end
end

defmodule BrandoIntegration.TestCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import Ecto.Query

      alias Ecto.Integration.Repo, as: Repo

      require Repo
    end
  end
end

defmodule BrandoIntegration.ModuleWithDatasource do
  @moduledoc false
  use Brando.Blueprint,
    application: "BrandoIntegration",
    domain: "Tests",
    schema: "ModuleWithDatasource",
    singular: "module_with_datasource",
    plural: "modules_with_datasource",
    gettext_module: Brando.Gettext

  attributes do
    attribute :title, :string
  end

  datasources do
    datasource :all do
      type :list
      list(fn _, _, _ -> {:ok, [1, 2, 3]} end)
    end

    datasource :featured do
      type :selection

      list(fn _schema, _language, _vars ->
        {:ok, [%{id: 1, label: "label 1"}, %{id: 2, label: "label 2"}]}
      end)

      get(fn _identifiers ->
        {:ok, [%{id: 1, label: "label 1", more: true}, %{id: 2, label: "label 2", more: true}]}
      end)
    end
  end
end

ExUnit.start()

Brando.Cache.Identity.set()
Brando.Cache.SEO.set()
Brando.Cache.Globals.set()

fixture_src = Path.expand(".", __DIR__) <> "/fixtures/sample.jpg"
media_path = Brando.config(:media_path)

File.mkdir_p!(Path.join([media_path, "images", "avatars"]))
File.cp!(fixture_src, Path.join([media_path, "images", "avatars", "27i97a.jpeg"]))

Ecto.Adapters.SQL.Sandbox.mode(BrandoIntegration.Repo, :manual)

Brando.endpoint().start_link()
