defmodule BrandoAdmin.Components.Form.StructuredDataTest do
  # The meta drawer's Structured data tab for an entry the site's JSON-LD
  # mapping can't describe: it says why in the tab, instead of taking the
  # drawer (and the entry's form with it) down.
  use Brando.ConnCase, async: false

  import Brando.Test.Support, only: [put_test_env: 2]
  import Phoenix.LiveViewTest, only: [rendered_to_string: 1]

  alias Brando.JSONLDTest.Shelf
  alias BrandoAdmin.Components.Form.StructuredData

  setup do
    put_test_env(Brando.JSONLDTest,
      shelves: [%Shelf{id: 1, title: "Broken", slug: "broken"}, %Shelf{id: 2, title: "Bare", slug: "bare", vars: []}]
    )

    :ok
  end

  defp load(entry_id) do
    {:ok, socket} = StructuredData.mount(%Phoenix.LiveView.Socket{})
    socket = Phoenix.Component.assign(socket, %{id: "structured-data", schema: Shelf, entry_id: entry_id, open: nil})
    {:noreply, socket} = StructuredData.handle_event("load", %{}, socket)
    socket
  end

  defp render_tab(socket) do
    socket.assigns
    |> Map.put(:myself, %Phoenix.LiveComponent.CID{cid: 1})
    |> StructuredData.render()
    |> rendered_to_string()
  end

  test "an entry whose field function raises shows the reason in the tab" do
    socket = load(1)

    assert socket.assigns.error == {:build_failed, "the shelf has no description"}

    html = render_tab(socket)
    assert html =~ ~s(data-testid="structured-data-build-failed")
    assert html =~ "Could not build structured data: the shelf has no description"
  end

  test "the reason is translated" do
    Gettext.put_locale(Brando.Gettext, "no")
    on_exit(fn -> Gettext.put_locale(Brando.Gettext, "en") end)

    assert render_tab(load(1)) =~ "Kunne ikke lage strukturerte data: the shelf has no description"
  end

  test "an entry the mapping describes still shows its graph" do
    socket = load(2)

    assert socket.assigns.error == nil
    assert socket.assigns.inspection
  end
end
