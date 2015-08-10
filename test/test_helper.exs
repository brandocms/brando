#Logger.configure(level: :info)
:erlang.system_flag(:backtrace_depth, 1000)
ExUnit.start

# Clear tmp dir
File.rm_rf!(Path.join([Mix.Project.app_path, "tmp", "media"]))
File.mkdir_p!(Path.join([Mix.Project.app_path, "tmp", "media"]))

# Basic test repo
alias Brando.Integration.TestRepo, as: Repo

defmodule Brando.Integration.TestRepo do
  use Ecto.Repo,
    otp_app: :brando
end

defmodule Brando.Integration.Endpoint do
  use Phoenix.Endpoint,
    otp_app: :brando

  plug Plug.Session,
    store: :cookie,
    key: "_test",
    signing_salt: "signingsalt",
    encryption_salt: "encsalt"

  plug Plug.Static,
    at: "/", from: :brando, gzip: false,
    only: ~w(css images js fonts favicon.ico robots.txt),
    cache_control_for_vsn_requests: nil,
    cache_control_for_etags: nil


  socket "/admin/ws", Brando.Integration.UserSocket

end

defmodule Brando.Integration.UserSocket do
  use Phoenix.Socket

  ## Channels
  channel "system:*", Brando.SystemChannel
  channel "stats", Brando.StatsChannel

  ## Transports
  transport :websocket, Phoenix.Transports.WebSocket
  transport :longpoll, Phoenix.Transports.LongPoll

  # Socket params are passed from the client and can
  # be used to verify and authenticate a user. After
  # verification, you can put default assigns into
  # the socket that will be set for all channels, ie
  #
  #     {:ok, assign(socket, :user_id, verified_user_id)}
  #
  #  To deny connection, return `:error`.
  def connect(_params, socket) do
    {:ok, socket}
  end

  # Socket id's are topics that allow you to identify all sockets for a given user:
  #
  #     def id(socket), do: "users_socket:#{socket.assigns.user_id}"
  #
  # Would allow you to broadcast a "disconnect" event and terminate
  # all active sockets and channels for a given user:
  #
  #     MyApp.Endpoint.broadcast("users_socket:" <> user.id, "disconnect", %{})
  #
  # Returning `nil` makes this socket anonymous.
  def id(_socket), do: nil
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

defmodule Forge do
  use Blacksmith

  @save_one_function &Blacksmith.Config.save/2
  @save_all_function &Blacksmith.Config.save_all/2

  register :user,
    __struct__: Brando.User,
    full_name: "James Williamson",
    email: "james@thestooges.com",
    password: "hunter2hunter2",
    username: "jamesw",
    avatar: nil,
    role: ["2", "4"],
    language: "no"

  register :user_w_hashed_pass,
    __struct__: Brando.User,
    full_name: "James Williamson",
    email: "james@thestooges.com",
    password: "$2b$12$VD9opg289oNQAHii8VVpoOIOe.y4kx7.lGb9SYRwscByP.tRtJTsa",
    username: "jamesw",
    avatar: nil,
    role: ["2", "4"],
    language: "no"
end

defmodule Blacksmith.Config do
  def save(repo, map) do
    repo.insert!(map)
  end

  def save_all(repo, list) do
    Enum.map(list, &repo.insert!/1)
  end
end

Code.require_file "support/migrations.exs", __DIR__

_   = Ecto.Storage.down(Repo)
:ok = Ecto.Storage.up(Repo)
{:ok, _pid} = Repo.start_link
:ok = Ecto.Migrator.up(Repo, 0, Brando.Integration.Migration, log: false)

Ecto.Adapters.SQL.begin_test_transaction(Brando.repo)
Brando.endpoint.start_link