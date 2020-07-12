# Logger.configure(level: :info)

# Clear tmp dir
File.rm_rf!(Path.join([Mix.Project.app_path(), "tmp", "media"]))
File.mkdir_p!(Path.join([Mix.Project.app_path(), "tmp", "media"]))

{:ok, _} = Application.ensure_all_started(:ex_machina)

Supervisor.start_link(
  [{Phoenix.PubSub, name: Brando.Integration.PubSub, pool_size: 1}],
  strategy: :one_for_one
)

ExUnit.start()

defmodule Brando.Integration.Repo do
  use Ecto.Repo,
    otp_app: :brando,
    adapter: Ecto.Adapters.Postgres

  use Brando.SoftDelete.Repo
end

defmodule Brando.Integration.Presence do
  use Phoenix.Presence, otp_app: :brando, pubsub_server: Brando.Integration.PubSub
end

defmodule Brando.Villain.ParserTest.Parser do
  use Brando.Villain.Parser
end

# Basic test repo
alias Brando.Integration.Repo, as: Repo

defmodule Brando.Integration.Endpoint do
  use Phoenix.Endpoint,
    otp_app: :brando

  socket "/admin/socket", Brando.Integration.AdminSocket,
    websocket: true,
    longpoll: false

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

defmodule Brando.Integration.Authorization do
  use Brando.Authorization

  types [{"User", Brando.Users.User}]

  # Rules for :superuser
  rules :superuser do
    can :manage, :all
  end
end

defmodule Brando.Integration.AdminSocket do
  @moduledoc """
  Socket specs for System and Stats channels.
  """
  use Phoenix.Socket

  ## Channels
  channel "admin", Brando.Integration.AdminChannel
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

defmodule Brando.Integration.AdminChannel do
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

defmodule Brando.Integration.Processor.Commands do
  def command(_, _, _) do
    {:ok, 0}
  end
end

defmodule Brando.Integration.PageView do
  use Phoenix.View, root: "test/fixtures/templates"
end

defmodule Brando.Integration.LayoutView do
  use Phoenix.View, root: "test/fixtures/templates"
end

defmodule Brando.Integration.LivePreview do
  use Brando.LivePreview

  target(
    schema_module: Brando.Pages.Page,
    view_module: Brando.Integration.PageView,
    layout_module: Brando.Integration.LayoutView,
    template: fn _ -> "index.html" end,
    section: fn _ -> "index" end,
    template_prop: :page
  ) do
    assign :test, fn ->
      "zapp"
    end
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

defmodule Brando.Integration.Guardian do
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

defmodule Brando.Integration.ModuleWithDatasource do
  use Brando.Datasource
  use Brando.Web, :schema

  schema "zapp" do
    field :title, :string
  end

  datasources do
    many :all,
         fn _, _ -> {:ok, [1, 2, 3]} end

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
Brando.Cache.Globals.set()

Ecto.Adapters.SQL.Sandbox.mode(Repo, :manual)
Brando.endpoint().start_link
Brando.presence().start_link
Brando.Registry.start_link()
Brando.Registry.register(Brando, [:gettext])
