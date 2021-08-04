defmodule BrandoAdmin.Components.PresenceEngine do
  use Surface.Component
  @topic "b:presence"

  prop user_id, :any, required: true
  data users, :list

  def mount(socket) do
    {:ok,
     socket
     |> subscribe()}
  end

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:users, fn ->
       list_opts = %{select: [:id, :avatar, :name], cache: {:ttl, :infinite}}

       {:ok, users} = Brando.Users.list_users(list_opts)

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
     end)}
  end

  def render(assigns) do
    ~F"""
    <span
      id="brando-presence"
      phx-hook="Brando.Presence" />
    """
  end

  def subscribe(socket) do
    Phoenix.PubSub.subscribe(Brando.pubsub(), @topic)

    socket
  end

  def handle_event("get_users", _, socket) do
    {:reply, %{users: socket.assigns.users}, socket}
  end

  def handle_event("get_state", _, socket) do
    {:reply, %{state: Brando.app_module(Presence).list(@topic)}, socket}
  end

  def handle_event("track", %{"userId" => user_id}, socket) do
    Brando.app_module(Presence).track(
      self(),
      @topic,
      user_id,
      %{online_at: inspect(System.system_time(:second)), active: true}
    )

    {:noreply, socket}
  end
end
