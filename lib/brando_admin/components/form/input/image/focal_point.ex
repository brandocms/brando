defmodule BrandoAdmin.Components.Form.Input.Image.FocalPoint do
  use Surface.Component
  # use Phoenix.LiveComponent
  use Phoenix.HTML

  prop field_name, :form
  prop focal, :any

  def render(assigns) do
    ~F"""
    {inspect @focal, pretty: true}
    {#if @focal}
      <div
        id={"input-image-#{@field_name}-focal"}
        class="focus-point"
        phx-hook="Brando.FocalPoint"
        data-field={"#{@field_name}"}
        data-x={"#{@focal.x}"}
        data-y={"#{@focal.y}"}>
        <div phx-update="ignore">
          <div class="focus-point-pin"></div>
        </div>
      </div>
    {/if}
    """
  end
end
