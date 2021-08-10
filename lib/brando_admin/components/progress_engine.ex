defmodule BrandoAdmin.Components.ProgressEngine do
  use Surface.LiveComponent
  @topic "b:progress"

  def mount(socket) do
    if connected?(socket) do
      subscribe()
    end

    {:ok, socket}
  end

  def render(assigns) do
    ~F"""
    <div class="progress-wrapper">
      <div class="progress">
        <div class="progress-item">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M18.364 5.636L16.95 7.05A7 7 0 1 0 19 12h2a9 9 0 1 1-2.636-6.364z"/></svg>
          <div class="filename">
            2hkf49azxt11.jpg
          </div>
          <div class="description">
            Creating resized version <code>xlarge</code>
          </div>
          <div class="percent">
            47%
          </div>
        </div>
        <div class="progress-item">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M12 22C6.477 22 2 17.523 2 12S6.477 2 12 2s10 4.477 10 10-4.477 10-10 10zm0-2a8 8 0 1 0 0-16 8 8 0 0 0 0 16zm1-8h4v2h-6V7h2v5z"/></svg>
          <div class="filename">
            4xzf4933oodz.jpg
          </div>
          <div class="description">
            Creating resized version <code>large</code>
          </div>
          <div class="percent">
            0%
          </div>
        </div>
      </div>
    </div>
    """
  end

  def subscribe do
    Phoenix.PubSub.subscribe(Brando.pubsub(), @topic)
  end
end
