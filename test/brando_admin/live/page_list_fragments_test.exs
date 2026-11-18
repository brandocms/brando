defmodule BrandoAdmin.Pages.PageListFragmentsTest do
  # The pages listing deletes a page with what the editor chose for its
  # fragments, and lists the fragments no page holds (#3621)
  use Brando.LiveCase, async: true

  alias Brando.Factory
  alias Brando.Pages.Fragment
  alias Brando.Pages.Page
  alias BrandoIntegration.Repo

  setup do
    parent = Factory.insert(:page, uri: "parent", title: "Parent")
    page = Factory.insert(:page, uri: "parent/child", title: "Child", parent_id: parent.id)
    other = Factory.insert(:page, uri: "other", title: "Other")
    fragment = Factory.insert(:fragment, page_id: page.id, parent_key: "partials", key: "footer", title: "Footer")
    %{parent: parent, page: page, other: other, fragment: fragment}
  end

  test "the delete dialog's choice decides where the fragments go", %{conn: conn, page: page, other: other} = ctx do
    {:ok, view, _html} = live(conn, "/admin/pages")

    render_click(view, "delete_entry", %{
      "id" => to_string(page.id),
      "fragments" => "move",
      "fragments_page" => to_string(other.id)
    })

    assert Repo.get!(Page, page.id).deleted_at
    assert Repo.get!(Fragment, ctx.fragment.id).page_id == other.id
  end

  test "deleting them with the page trashes them", %{conn: conn, page: page, fragment: fragment} do
    {:ok, view, _html} = live(conn, "/admin/pages")

    render_click(view, "delete_entry", %{"id" => to_string(page.id), "fragments" => "delete"})

    assert Repo.get!(Fragment, fragment.id).deleted_at == Repo.get!(Page, page.id).deleted_at
  end

  test "moving them to no page lists them under Fragments without a page", %{conn: conn, page: page} do
    {:ok, view, html} = live(conn, "/admin/pages")
    refute html =~ "fragments-without-page-title"

    render_click(view, "delete_entry", %{"id" => to_string(page.id), "fragments" => "move", "fragments_page" => ""})

    # The section reloads two messages after the click: the view handles the
    # listing's broadcast, then the `send_update` that handler queues for it
    await_selector(view, "#fragments-without-page-title")
    assert view |> element("#fragments-without-page .child-chip") |> render() =~ "partials/footer"
  end

  test "Fragments without a page follows the content language", %{conn: conn} do
    Factory.insert(:fragment, page_id: nil, parent_key: "partials", key: "bunntekst", language: :no)
    {:ok, view, html} = live(conn, "/admin/pages")
    refute html =~ "partials/bunntekst"

    send(view.pid, {:set_content_language, "no"})

    assert render(view) =~ "partials/bunntekst"
  end

  test "a target page in the trash leaves the page where it was", %{conn: conn, page: page, other: other} = ctx do
    {:ok, _} = Brando.Repo.soft_delete(other)
    {:ok, view, _html} = live(conn, "/admin/pages")

    render_click(view, "delete_entry", %{
      "id" => to_string(page.id),
      "fragments" => "move",
      "fragments_page" => to_string(other.id)
    })

    assert is_nil(Repo.get!(Page, page.id).deleted_at)
    assert Repo.get!(Fragment, ctx.fragment.id).page_id == page.id
  end

  test "a bulk delete moves the fragments to the parent", %{conn: conn, page: page, other: other} = ctx do
    {:ok, view, _html} = live(conn, "/admin/pages")

    render_click(view, "delete_selected", %{"ids" => Jason.encode!([page.id, other.id])})

    assert Repo.get!(Page, page.id).deleted_at
    assert Repo.get!(Fragment, ctx.fragment.id).page_id == ctx.parent.id
  end
end
