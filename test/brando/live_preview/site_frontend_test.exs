defmodule Brando.LivePreview.SiteFrontendTest do
  # Not async: it sets :site_frontends.
  use Brando.ConnCase, async: false

  alias Brando.LivePreview
  alias Brando.Pages.Page
  alias Brando.Tenant
  alias Brando.Tenant.Registry

  defmodule AcmeLayouts do
    @moduledoc false
    use Phoenix.Component

    def root(assigns) do
      ~H|<html data-site="acme">
  <body>
    {@inner_content}
    <footer>{@footer}{@footer_color}</footer>
  </body>
</html>|
    end
  end

  defmodule AcmePageHTML do
    @moduledoc false
    use Phoenix.Component

    def default(assigns), do: ~H|<main>{@page.title}</main>|
  end

  defmodule Acme do
    @moduledoc false
    use Brando.Site.Frontend, root_layout: {AcmeLayouts, :root}, page_html: AcmePageHTML

    def layout_assigns(language), do: %{footer: "footer:#{language}", footer_color: "none"}
    def page_assigns(page, assigns), do: %{footer_color: ":#{page.uri}:#{assigns.language}"}
  end

  setup do
    put_test_env(:tenancy_mode, :multi)
    put_test_env(:site_frontends, %{"preview-acme" => Acme})

    {:ok, site} =
      Registry.create_site(%{
        name: "Acme",
        key: "preview-acme",
        languages: ["en", "no"],
        default_language: "en",
        status: :active,
        delivery_mode: :dynamic
      })

    {:ok, _environment} =
      Registry.create_environment(site, %{name: "Production", key: "production", live: true}, actor: :system)

    Tenant.put_prefix("tenant_preview-acme_production")

    on_exit(fn ->
      Tenant.put_prefix(nil)
      Tenant.Cache.clear()
    end)

    :ok
  end

  test "a page previews in its site's layout and template, with the site's layout and page assigns" do
    page = %Page{title: "About", uri: "about", template: "default.html", language: :no, entry_blocks: []}

    html = Page |> LivePreview.render(page, nil, target: :site) |> String.replace(~r/>\s+</, "><")

    assert html ==
             ~s(<html data-site="acme"><body><main>About</main><footer>footer:no:about:no</footer></body></html>)
  end
end
