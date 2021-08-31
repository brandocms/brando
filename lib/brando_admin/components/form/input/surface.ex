defmodule BrandoAdmin.Components.Form.Input.Surface do
  use Surface.Component
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.FieldBase
  alias BrandoAdmin.Components.Form.Input.SurfaceMacro
  alias Surface.Components.Form.TextInput

  def mount(socket) do
    tpl =
      quote_surface do
        ~F"""
        HELLO!
        """
      end

    {:ok, assign(socket, :template, tpl)}
  end

  def render(assigns) do
    quote_surface do
      ~F"""
      {^assigns}
      """
    end
  end
end
