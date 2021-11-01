defmodule BrandoAdmin.Components.Badge do
  use Phoenix.Component

  def language(assigns) do
    ~H"""
    <div class="circle circle-flag">
      <%= @language %>
    </div>
    """
  end
end
