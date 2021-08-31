defmodule BrandoAdmin.Components.Content.Header do
  use Surface.Component

  prop title, :string, required: true
  prop subtitle, :string

  slot default

  def render(assigns) do
    ~F"""
    <header id="content-header" data-moonwalk-run="brandoHeader">
      <div class="content">
        <section class="main">
          <h1>
            {@title}
          </h1>
          <h3>
            {@subtitle}
          </h3>
        </section>
        <section class="actions">
          <#slot />
        </section>
      </div>
    </header>
    """
  end
end
