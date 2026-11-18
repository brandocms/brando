defmodule BrandoAdmin.RenderFailureSaveTest do
  # An editor's save renders the entry inline. When a block template fails,
  # the entry's fields and blocks save, its stored HTML stays as it was, and
  # the editor is told which block failed and why, on the entry.
  # Grouped, as BrandoAdmin.RenderStoreOrderTest: ProposalFixtures.context/0
  # inserts pages whose URIs concurrent transactions would wait on.
  use Brando.LiveCase, async: true, group: :shared_locks

  import Brando.EditSessionEditors
  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Blocks
  alias Brando.Pages.Page

  @moduletag :capture_log

  setup %{conn: conn} do
    c = Brando.ProposalFixtures.context()
    {:ok, _} = Blocks.render_entry(Page, c.identity.id)
    [first | _] = rows(c.identity)
    Map.merge(c, %{conn: conn, first: first.block.uid, stored: rendered(c.identity)})
  end

  test "a save whose block template fails saves the entry, keeps its HTML and says which block failed", c do
    {view, _html} = live_form(c.conn, "/admin/pages/update/#{c.identity.id}")
    await_selector(view, "[data-block-uid]")

    # The template breaks after the editor opened the entry
    {1, _} =
      Repo.update_all(from(m in Brando.Content.Module, where: m.id == ^c.text_module.id),
        set: [code: ~s(<p>{{ "x" | no_such_filter }}</p>)]
      )

    type(view, c.first, "<p>Saved by the editor</p>")
    view |> form("#page_form_form", page: %{title: "Renamed by the editor"}) |> render_submit()
    assert_push_event(view, "b:submit", %{}, 5_000)
    view |> form("#page_form_form", page: %{title: "Renamed by the editor"}) |> render_submit()

    # Names the block's module and the error
    assert_push_event(view, "b:alert", %{type: "error", html: html}, 5_000)
    assert html =~ "Text"
    assert html =~ "no_such_filter"

    page = Repo.get!(Page, c.identity.id)
    assert page.title == "Renamed by the editor"
    assert page.rendered_blocks == c.stored
    assert Enum.any?(rows(c.identity), &(inspect(&1.block.refs) =~ "Saved by the editor"))
  end

  defp rendered(page), do: Repo.get!(Page, page.id).rendered_blocks
end
