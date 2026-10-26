defmodule Brando.Villain.LinkSchemeTest do
  # Addresses editors type (a link var, a picture's link, a menu item, a
  # service) render as links only with a scheme Brando.RichText allows. A
  # script address renders an inert element instead. The payloads only set
  # the document title.
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1, render_component: 2]

  alias Brando.Content.Var
  alias Brando.Villain.Components

  @scripts [
    "javascript:document.title='link-scheme'",
    "JaVaScRiPt:document.title='link-scheme'",
    "  javascript:document.title='link-scheme'",
    "java\tscript:document.title='link-scheme'",
    "&#106;avascript:document.title='link-scheme'",
    "data:text/html,<title>link-scheme</title>",
    "vbscript:msgbox"
  ]

  defp link_var(url), do: %Var{type: :link, link_type: :url, value: url, link_text: "Text", link_target_blank: false}

  defp entry_link(attrs) do
    assigns =
      Map.merge(%{href: nil, entry: nil, field: :url, var: nil, class: nil, inner_block: [], __changed__: %{}}, attrs)

    rendered_to_string(Components.entry_link(assigns))
  end

  test "entry_link renders a script address inert, from an href, a var or the entry" do
    for url <- @scripts do
      for html <- [
            entry_link(%{href: url}),
            entry_link(%{var: link_var(url)}),
            entry_link(%{entry: %{url: url}})
          ] do
        refute html =~ "href", "#{inspect(url)}: #{html}"
      end
    end

    assert entry_link(%{var: link_var("https://brandocms.com")}) =~ ~s(href="https://brandocms.com")
    assert entry_link(%{href: "/projects/a"}) =~ ~s(href="/projects/a")
    assert entry_link(%{entry: %{url: "mailto:post@example.com"}}) =~ ~s(href="mailto:post@example.com")
  end

  test "the link_url filter gives no address for a script" do
    for url <- @scripts, do: assert(Brando.Villain.Filters.link_url(link_var(url), nil) == nil)
    assert Brando.Villain.Filters.link_url(link_var("/about"), nil) == "/about"
  end

  test "a picture links only to a safe address" do
    picture = fn link ->
      :image |> Brando.Factory.build(%{alt: "Alt", link: link}) |> Brando.Villain.Parser.picture([])
    end

    for url <- @scripts do
      html = picture.(url)
      refute html =~ "<a", "#{inspect(url)}: #{html}"
      refute html =~ "link-scheme"
    end

    assert picture.("https://example.com") =~ ~s(href="https://example.com")
  end

  test "a menu item or a service links only to a safe address" do
    for url <- @scripts do
      assert Brando.HTML.get_menu_item_url(%{link: %{link_type: :url, value: url}}) == nil

      html =
        render_component(&Brando.HTML.Services.list/1,
          services: [%Brando.Sites.Service{name: "Service", url: url}]
        )

      refute html =~ "href", "#{inspect(url)}: #{html}"
    end

    assert Brando.HTML.get_menu_item_url(%{link: %{link_type: :url, value: "/about"}}) == "/about"
  end

  test "the Markdown export gives a script link no address" do
    for url <- @scripts, do: assert(Brando.Villain.Markdown.HTML.link_url(url) == nil)
  end
end
