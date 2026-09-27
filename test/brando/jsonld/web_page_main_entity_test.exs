defmodule Brando.JSONLD.Schema.WebPageMainEntityTest do
  use ExUnit.Case, async: true

  alias Brando.JSONLD.Schema.WebPage

  defp page(type) do
    :get
    |> Plug.Test.conn("/about")
    |> Plug.Conn.assign(:json_ld_page_type, type)
    |> WebPage.build(nil, nil)
  end

  test "a profile or about page is about the site identity" do
    identity = %{"@id": Path.join(Brando.Utils.hostname(), "#identity")}

    assert page("ProfilePage").mainEntity == identity
    assert page("AboutPage").mainEntity == identity
  end

  test "other pages have no mainEntity" do
    assert page("WebPage").mainEntity == nil
    assert page("CollectionPage").mainEntity == nil
  end
end
