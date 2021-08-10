defmodule BrandoAdmin.Components.ToastEngine do
  use Surface.LiveComponent
  @topic "b:toast"

  def mount(socket) do
    if connected?(socket) do
      subscribe()
    end

    {:ok, socket}
  end

  def render(assigns) do
    ~F"""
    <span />
    """
  end

  def subscribe do
    Phoenix.PubSub.subscribe(Brando.pubsub(), @topic)
  end
end
