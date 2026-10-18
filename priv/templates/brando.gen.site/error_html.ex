defmodule <%= web_module %>.ErrorHTML do
  @moduledoc """
  Renders HTML error pages, for the endpoint (`render_errors` in
  config/config.exs) and for Brando's fallback controller.

  404 and 500 render the templates in error_html/ inside the site's root
  layout, `<%= web_module %>.CMS.Layouts.root/1`. Other statuses render their
  status message as plain text.
  """
  use BrandoWeb, :html

  require Logger

  embed_templates "error_html/*"

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end

  @doc """
  Wraps an error message in the site's root layout.

  A CMS page that was not found is rendered inside that layout already. The
  endpoint renders errors without a layout, with the conn as it was when the
  error was raised, so the layout gets that conn's assigns, the default
  language when its pipeline never set one, and the `partials` fragments for
  its footer when its controller never assigned them. If the layout raises
  (say, the database is down and its caches are cold), the error is logged and
  the page renders without it. Without a conn, only the message renders.
  """
  attr :conn, Plug.Conn, default: nil
  slot :inner_block, required: true

  def error_page(%{conn: %Plug.Conn{} = conn} = assigns) do
    if Phoenix.Controller.root_layout(conn, "html"),
      do: content(assigns),
      else: in_layout(assigns)
  end

  def error_page(assigns), do: content(assigns)

  # Rendered to iodata here rather than when the response is sent, so that an
  # error the layout raises is rescued.
  defp in_layout(assigns) do
    layout_assigns = Map.put_new(assigns.conn.assigns, :language, Brando.config(:default_language))

    page =
      layout_assigns
      |> Map.put_new_lazy(:partials, fn -> partials(layout_assigns.language) end)
      |> Map.merge(%{conn: assigns.conn, inner_content: content(assigns), __changed__: nil})
      |> <%= web_module %>.CMS.Layouts.root()
      |> Phoenix.HTML.Safe.to_iodata()

    assigns = assign(assigns, :page, {:safe, page})

    ~H"{@page}"
  rescue
    exception ->
      Logger.error(
        "The error page rendered without the site's layout, which raised:\n" <>
          Exception.format(:error, exception, __STACKTRACE__)
      )

      bare(assigns)
  end

  defp partials(language) do
    {:ok, partials} =
      Brando.Pages.get_fragments(%{
        filter: %{parent_key: "partials", language: language},
        cache: {:ttl, :infinite}
      })

    partials
  end

  defp bare(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang={Brando.config(:default_language)}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
      </head>
      <body>
        <.content inner_block={@inner_block} />
      </body>
    </html>
    """
  end

  defp content(assigns) do
    ~H"""
    <main id="content" class="error-page">
      <section class="page-section">
        <div class="inner">
          {render_slot(@inner_block)}
        </div>
      </section>
    </main>
    """
  end
end
