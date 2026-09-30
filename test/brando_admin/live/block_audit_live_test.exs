defmodule BrandoAdmin.BlockAuditLiveTest do
  # Utilities → Loose blocks: lists the block trees no entry links to,
  # removes the selected removable ones to the archive, and restores them.
  use Brando.LiveCase

  import Ecto.Query

  alias Brando.Content.Block
  alias Brando.Pages.Page
  alias Brando.Repo

  @source "Elixir.Brando.Pages.Page.Blocks"
  @path "/admin/config/utils/loose-blocks"

  setup do
    page = Factory.insert(:page, title: "About us", uri: "about-us", language: "en")
    linked = Repo.insert!(%Block{type: :module, source: @source, uid: Brando.Utils.generate_uid()})
    Repo.insert!(%Page.Blocks{entry_id: page.id, block_id: linked.id, sequence: 0})

    loose =
      Repo.insert!(%Block{type: :module, source: @source, uid: Brando.Utils.generate_uid(), description: "Old hero"})

    %{page: page, linked: linked, loose: loose}
  end

  test "lists loose trees, removes the selected one and restores it", %{conn: conn} = c do
    {:ok, view, html} = live(conn, @path)

    assert html =~ "Old hero"
    assert html =~ "pages_blocks"
    assert has_element?(view, ~s(input[phx-value-id="#{c.loose.id}"]))
    refute has_element?(view, ~s(input[phx-value-id="#{c.linked.id}"]))
    assert has_element?(view, "button[phx-click=remove][disabled]")

    view |> element("button[phx-click=select_all]") |> render_click()
    refute has_element?(view, "button[phx-click=remove][disabled]")

    html = view |> element("button[phx-click=remove]") |> render_click()
    refute Repo.get(Block, c.loose.id)
    assert Repo.get(Block, c.linked.id)
    assert html =~ "block-audit-archive"

    view |> element("button[phx-click=restore]") |> render_click()
    assert Repo.get(Block, c.loose.id).description == "Old hero"
  end

  test "a linked block's id cannot be removed by sending its id", %{conn: conn} = c do
    {:ok, view, _html} = live(conn, @path)

    render_click(view, "toggle", %{"id" => to_string(c.linked.id)})
    render_click(view, "remove", %{})

    assert Repo.get(Block, c.linked.id)
    assert Repo.one(from j in Page.Blocks, where: j.block_id == ^c.linked.id, select: count()) == 1
  end

  test "the utilities page links to it", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/admin/config/utils")
    assert html =~ @path
  end
end
