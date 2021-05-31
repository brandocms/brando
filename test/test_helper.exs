# Logger.configure(level: :debug)

# Clear tmp dir
File.rm_rf!(Path.join([Mix.Project.app_path(), "tmp", "media"]))
File.mkdir_p!(Path.join([Mix.Project.app_path(), "tmp", "media"]))

{:ok, _} = Application.ensure_all_started(:ex_machina)

defmodule BrandoIntegration.Repo do
  use Ecto.Repo,
    otp_app: :brando,
    adapter: Ecto.Adapters.Postgres

  use Brando.SoftDelete.Repo
end

defmodule BrandoIntegration.DummyRepo do
  use Ecto.Repo,
    otp_app: :brando,
    adapter: Ecto.Adapters.Postgres

  use Brando.SoftDelete.Repo
end

Supervisor.start_link(
  [{Phoenix.PubSub, name: BrandoIntegration.PubSub, pool_size: 1}, Brando],
  strategy: :one_for_one
)

ExUnit.start()

defmodule BrandoIntegration.Presence do
  use Phoenix.Presence, otp_app: :brando, pubsub_server: BrandoIntegration.PubSub
end

defmodule BrandoIntegrationWeb.Gettext do
  use Gettext, otp_app: :brando, priv: "priv/gettext/frontend"
end

defmodule Brando.Villain.ParserTest.Parser do
  use Brando.Villain.Parser
end

# Basic test repo
alias BrandoIntegration.Repo, as: Repo

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
  use Brando.Authorization

  types [{"User", Brando.Users.User}]

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
  channel "admin", BrandoIntegration.AdminChannel
  channel "user:*", Brando.UserChannel
  channel "live_preview:*", Brando.LivePreviewChannel

  @doc """
  Connect socket with token
  """
  @impl true
  def connect(%{"guardian_token" => _jwt}, socket) do
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

defmodule BrandoIntegration.AdminChannel do
  @moduledoc """
  Administration control channel
  """

  use Phoenix.Channel
  use Brando.Mixin.Channels.AdminChannelMixin

  # ++imports
  use Brando.Sequence.Channel
  # __imports

  # ++macros
  # __macros

  # ++functions
  # __functions

  # def handle_in("domain:action", %{"params" => params}, socket) do
  #   {:reply, {:ok, %{code: 200, params: params}}, socket}
  # end
end

defmodule BrandoIntegration.Processor.Commands do
  def command(_, _, _), do: {:ok, 0}
end

defmodule BrandoIntegrationWeb.PageView do
  use Phoenix.View, root: "test/fixtures/templates"
end

defmodule BrandoIntegrationWeb.LayoutView do
  use Phoenix.View, root: "test/fixtures/templates"
end

defmodule BrandoIntegrationWeb.LivePreview do
  use Brando.LivePreview

  preview_target Brando.Pages.Page do
    view_module BrandoIntegrationWeb.PageView
    layout_module BrandoIntegrationWeb.LayoutView
    view_template fn _ -> "index.html" end
    template_section fn _ -> "index" end
    template_prop :page
    assign :test, fn _ -> "zapp" end
  end
end

defmodule CompileTimeAssertions do
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
  use ExUnit.CaseTemplate

  using do
    quote do
      require Repo
      import Ecto.Query
      alias Ecto.Integration.Repo, as: Repo
    end
  end
end

defmodule BrandoIntegration.Guardian do
  def encode_and_sign(user) do
    {:ok, "user:#{user.id}", %{}}
  end

  def decode_and_verify(jwt) do
    {:ok, jwt}
  end

  def resource_from_claims("user:" <> id) do
    Brando.Users.get_user(id)
  end

  def revoke(token) do
    token
  end
end

defmodule BrandoIntegration.ModuleWithDatasource do
  use Brando.Datasource
  use BrandoAdmin, :schema

  schema "zapp" do
    field :title, :string
  end

  datasources do
    list :all, fn _, _ -> {:ok, [1, 2, 3]} end

    selection :featured,
              fn _, _ ->
                {:ok, [%{id: 1, label: "label 1"}, %{id: 2, label: "label 2"}]}
              end,
              fn _, _ ->
                {:ok,
                 [%{id: 1, label: "label 1", more: true}, %{id: 2, label: "label 2", more: true}]}
              end
  end
end

Mix.Task.run("ecto.drop", ["-r", Repo, "--quiet"])
Mix.Task.run("ecto.create", ["-r", Repo, "--quiet"])
Mix.Task.run("ecto.migrate", ["-r", Repo, "--quiet"])
Repo.start_link()
Mix.Task.run("ecto.seed", ["-r", Repo, "--quiet"])

Brando.Cache.Identity.set()
Brando.Cache.SEO.set()
Brando.Cache.Globals.set()

Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
Brando.endpoint().start_link
Brando.presence().start_link
