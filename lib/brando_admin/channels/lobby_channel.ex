defmodule Brando.LobbyChannel do
  @moduledoc """
  Channel for all users (mostly toast updates)
  """

  use Phoenix.Channel

  # intercept([
  #   "alert",
  #   "set_progress",
  #   "increase_progress"
  # ])

  @doc """
  Join lobby channel
  """
  def join("lobby", _params, socket) do
    list_opts = %{select: [:id, :name], cache: {:ttl, :infinite}, preload: [{:avatar, :join}]}
    {:ok, users} = Brando.Users.list_users(list_opts)

    users =
      Enum.map(
        users,
        &%{
          name: &1.name,
          id: &1.id,
          avatar:
            Brando.Utils.img_url(&1.avatar, :medium,
              prefix: "/media",
              default: "/images/admin/avatar.svg"
            )
        }
      )

    send(self(), :after_join)
    {:ok, %{users: users}, socket}
  end

  def handle_info(:after_join, socket) do
    {:ok, _} =
      Brando.presence().track(socket, socket.assigns.user_id, %{
        online_at: inspect(System.system_time(:second)),
        active: true
      })

    push(socket, "presence_state", Brando.presence().list(socket))
    {:noreply, socket}
  end
end
