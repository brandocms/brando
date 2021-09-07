defmodule BrandoAdmin.Components.Identifier do
  use Surface.Component
  use Phoenix.HTML

  alias BrandoAdmin.Components.Identifier
  import Brando.Gettext

  prop identifier, :map

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)}
  end

  def render(assigns) do
    ~F"""
    <article class="identifier">
      <section class="cover-wrapper">
        <div class="cover">
          <img src={@identifier.cover}>
        </div>
      </section>
      <section class="content">
        <div class="info">
          <div class="name">
            {@identifier.title}
          </div>
          <div class="meta-info">
            {@identifier.type}
          </div>
        </div>
      </section>
    </article>
    """
  end
end
