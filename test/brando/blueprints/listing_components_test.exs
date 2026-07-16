defmodule Brando.Blueprint.ListingComponentsTest do
  use ExUnit.Case, async: true

  import Phoenix.LiveViewTest, only: [render_component: 2]

  alias Brando.Blueprint.Listings.Components
  alias Brando.Blueprint.Listings.Components.Core
  alias Brando.Blueprint.Listings.Components.Cover
  alias Brando.Pages.Page
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Image

  test "keeps core compatibility wrappers byte-for-byte equivalent" do
    Gettext.put_locale("no")

    i18n_attrs = %{map: %{"en" => "Hello", "no" => "Hei"}}
    assert render_component(&Core.i18n/1, i18n_attrs) == render_component(&Components.i18n/1, i18n_attrs)

    url_attrs = %{entry: %Page{id: 1, status: :draft, language: "en", uri: "index"}}
    assert render_component(&Core.url/1, url_attrs) == render_component(&Components.url/1, url_attrs)
  end

  test "keeps cover and image compatibility wrappers byte-for-byte equivalent" do
    cover_attrs = %{image: nil, columns: 2, size: :thumb}
    assert render_component(&Cover.cover/1, cover_attrs) == render_component(&Components.cover/1, cover_attrs)

    image_attrs = %{image: nil, size: :thumb}
    assert render_component(&Image.image/1, image_attrs) == render_component(&Content.image/1, image_attrs)
  end
end
