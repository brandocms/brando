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

  # The admin navigation's brand while this site is selected, in place of
  # config :brando, :client_brand. Trusted HTML, as client_brand is:
  #
  #     def admin_brand, do: ~s(<img src="/images/<%= key %>-logo.svg" alt="">)
end
