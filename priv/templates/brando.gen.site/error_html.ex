defmodule <%= web_module %>.ErrorHTML do
  @moduledoc """
  Renders HTML error pages, for the endpoint (`render_errors` in
  config/config.exs) and for Brando's fallback controller.

  404 and 500 render the templates in error_html/ inside the site's root
  layout, `<%= web_module %>.CMS.Layouts.root/1`. Other statuses render their
  status message as plain text.
  """
  use BrandoWeb, :html

  embed_templates "error_html/*"

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end

  @doc """
  Wraps an error message in the site's root layout.

  A CMS page that was not found is rendered inside that layout already. The
  endpoint renders errors without a layout, with the conn as it was when the
  error was raised, so the layout gets that conn's assigns and the default
  language when its pipeline never set one.
  """
  attr :conn, Plug.Conn, required: true
  slot :inner_block, required: true

  def error_page(assigns) do
    if Phoenix.Controller.root_layout(assigns.conn, "html") do
      content(assigns)
    else
      assigns.conn.assigns
      |> Map.put_new(:language, Brando.config(:default_language))
      |> Map.merge(%{conn: assigns.conn, inner_content: content(assigns), __changed__: nil})
      |> <%= web_module %>.CMS.Layouts.root()
    end
  end

  defp content(assigns) do
    ~H"""
    <main id="content" class="error-page">
      {render_slot(@inner_block)}
    </main>
    """
  end
end
