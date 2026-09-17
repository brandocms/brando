defmodule <%= web_module %>.CMS.Layouts do
  use BrandoWeb, :html

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang={@language}>
      <.head conn={@conn} />
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
