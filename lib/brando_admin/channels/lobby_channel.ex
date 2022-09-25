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
        fn user ->
          avatar =
            if user.avatar && Brando.Images.Utils.image_type(user.avatar.path) == :svg do
              Brando.Utils.img_url(user.avatar, :original,
                prefix: "/media",
                default: "/images/admin/avatar.svg"
              )
            else
              Brando.Utils.img_url(user.avatar, :smallest,
                prefix: "/media",
                default: "/images/admin/avatar.svg"
              )
            end

          %{
            name: user.name,
            id: user.id,
            avatar: avatar
          }
        end
      )

    send(self(), :after_join)
    {:ok, %{users: users}, socket}
  end

  def handle_in("user:state", %{"active" => active}, socket) do
    Brando.presence().update(socket, socket.assigns.user_id, fn state ->
      %{state | online_at: inspect(System.system_time(:second)), active: active}
    end)

    {:reply, :ok, socket}
  end

  def handle_in("user:state", %{"url" => url}, socket) do
    uri = URI.parse(url)

    Brando.presence().update(socket, socket.assigns.user_id, fn state ->
      %{state | online_at: inspect(System.system_time(:second)), url: uri.path}
    end)

    {:reply, :ok, socket}
  end

  def handle_info({_, {:uri_presence, _}}, socket) do
    # we don't care about uri presence updates here
    {:noreply, socket}
  end

  def handle_info(:after_join, socket) do
    {:ok, _} =
      Brando.presence().track(socket, socket.assigns.user_id, %{
        online_at: inspect(System.system_time(:second)),
        active: true,
        url: nil
      })

    push(socket, "presence_state", Brando.presence().list(socket))
    {:noreply, socket}
  end
end
