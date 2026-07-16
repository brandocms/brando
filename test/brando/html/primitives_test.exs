defmodule Brando.HTML.PrimitivesTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.HTML.I18n
  alias Brando.HTML.Icon

  test "renders icons through the leaf and compatibility components" do
    attrs = %{name: "hero-link", class: "small"}

    leaf_html = render_component(&Icon.icon/1, attrs)
    compatibility_html = render_component(&Brando.HTML.icon/1, attrs)

    assert leaf_html == compatibility_html
    assert leaf_html =~ "data-icon"
    assert leaf_html =~ ~s(class="hero-link small")
  end

  test "resolves translated maps through the leaf and compatibility components" do
    Gettext.put_locale("no")
    attrs = %{map: %{"en" => "Hello", "no" => "Hei"}}

    assert render_component(&I18n.i18n/1, attrs) == "Hei"
    assert render_component(&Brando.HTML.i18n/1, attrs) == "Hei"
  end

  test "falls back to the configured locale, then English" do
    Gettext.put_locale("de")

    assert render_component(&I18n.i18n/1, %{map: %{"en" => "Hello"}}) == "Hello"
    assert render_component(&I18n.i18n/1, %{map: nil}) == ""
  end
end
