defmodule <%= module %> do
  @moduledoc """
  The frontend of the site with key "<%= key %>": its root layout and page
  templates, registered in `config :brando, site_frontends`.
  """
  use Brando.Site.Frontend,
    root_layout: {<%= module %>.Layouts, :root},
    page_html: <%= module %>.PageHTML

  # Assigns for the root layout, per language:
  #
  #     def layout_assigns(language),
  #       do: %{footer_menu: Brando.Cache.Navigation.get("footer", language)}

  # Assigns for each page, after the page controller assigns it:
  #
  #     def page_assigns(page, _assigns),
  #       do: %{footer_color: Brando.Pages.get_var(page, "footer_color")}
end
