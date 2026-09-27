defmodule BrandoAdmin.LiveView.ListingPageTitleTest do
  use ExUnit.Case, async: true

  alias BrandoAdmin.LiveView.Listing

  defp socket, do: Phoenix.Component.assign(%Phoenix.LiveView.Socket{}, :page_title, "Features")

  test "keeps the schema's plural without a page_title" do
    assert {:cont, %{assigns: %{page_title: "Features"}}} = Listing.put_page_title({:cont, socket()}, nil)
  end

  test "a string or a function names the tab" do
    assert {:cont, %{assigns: %{page_title: "Front page"}}} = Listing.put_page_title({:cont, socket()}, "Front page")
    assert {:cont, %{assigns: %{page_title: "Forside"}}} = Listing.put_page_title({:cont, socket()}, fn -> "Forside" end)
  end

  test "leaves a halted mount alone" do
    halted = {:halt, socket()}
    assert Listing.put_page_title(halted, "Front page") == halted
  end
end
