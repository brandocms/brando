defmodule BrandoAdmin.Components.Badge do
  @moduledoc false
  use BrandoAdmin, :component

  def language(assigns) do
    ~H"""
    <div class="circle circle-flag">
      {@language}
    </div>
    """
  end
end
