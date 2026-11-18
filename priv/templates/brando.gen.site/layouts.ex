defmodule <%= module %> do
  use BrandoWeb, :html

  # A root layout gets the conn's assigns as a plain map, where `assign/3`
  # raises. Add to it with `Map.merge/2`:
  #
  #     assigns = Map.merge(assigns, %{year: Date.utc_today().year})
  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html class="no-js" lang={@language}>
      <.head conn={@conn}>
        <%%!-- The site's icons, in assets/frontend/public/ico/, which the frontend build
        copies to priv/static/ico/. Replace the files there and keep these lines in step. --%>
        <link rel="icon" href="/ico/favicon.ico" sizes="any" />
        <%%!-- More icons: add the file to public/ico/ and its line here.
        <link rel="icon" type="image/svg+xml" href="/ico/favicon.svg" />
        <link rel="icon" type="image/svg+xml" href="/ico/favicon-dark.svg" media="(prefers-color-scheme: dark)" />
        <link rel="icon" type="image/png" sizes="32x32" href="/ico/favicon-32.png" />
        <link rel="apple-touch-icon" href="/ico/apple-touch-icon.png" />
        --%>
      </.head>
      <.body_tag conn={@conn} id="top">
        <header data-nav>
          <nav aria-label="Menu">
            <a :if={site_name(assigns)} class="brand" href="/">{site_name(assigns)}</a>

            <ul :if={assigns[:navigation]}>
              <.menu :let={item} menu={@navigation}>
                <li>
                  <.menu_item :let={text} conn={@conn} item={item}>{text}</.menu_item>
                </li>
              </.menu>
            </ul>
          </nav>
        </header>

        {@inner_content}

        <footer>
          <div class="inner">
            {assigns[:partials] && @partials["footer"]}
            <div :if={site_name(assigns)} class="colophon">
              <p>© {Date.utc_today().year} {site_name(assigns)}</p>
            </div>
          </div>
        </footer>
      </.body_tag>
    </html>
    """
  end

  # Identity is cached per language and is an empty map until it is seeded.
  defp site_name(%{identity: %{name: name}}) when is_binary(name) and name != "", do: name
  defp site_name(_assigns), do: nil
end
