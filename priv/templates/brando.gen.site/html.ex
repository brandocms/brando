defmodule <%= module %> do
  use BrandoWeb, :html

  def index(assigns), do: default(assigns)

  def default(assigns) do
    ~H"""
    <main id="content">
      {@page}
    </main>
    """
  end
end
