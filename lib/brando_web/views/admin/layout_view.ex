defmodule BrandoWeb.LayoutView do
  @moduledoc """
  Main layout view for Brando admin.
  """
  use BrandoWeb, :view

  def render(_, assigns) do
    ~H"""
    {{ raw("<!DOCTYPE html>") }}
    <html lang="en">
      <head>
        {{ Phoenix.HTML.Tag.csrf_meta_tag() }}
        {{ live_title_tag assigns[:page_title] || "Brando" }}
        <script type="module" src="http://localhost:3333/@vite/client"></script>
        <script type="module" src="http://localhost:3333/src/main.js"></script>
      </head>
      <body>
        {{ @inner_content }}
      </body>
    </html>
    """
  end
end
