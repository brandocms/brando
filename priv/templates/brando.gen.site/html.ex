defmodule <%= web_module %>.CMS.PageHTML do
  use BrandoWeb, :html

  def index(assigns), do: default(assigns)

  def default(assigns) do
    ~H"""
    <main id="content">
      <h1>{@page.title}</h1>
      {@page}
    </main>
    """
  end
end
