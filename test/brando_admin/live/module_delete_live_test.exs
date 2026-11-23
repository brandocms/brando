defmodule BrandoAdmin.ModuleDeleteLiveTest do
  # The module listing's Delete: a module that blocks use is refused
  # (`Brando.Content.guard_delete/2`), and its dialog names the entries using
  # it, linked, with no Delete to confirm (#3882).
  use Brando.LiveCase, async: true

  alias Brando.Content.Module
  alias Brando.Factory
  alias Brando.Pages.Page

  setup %{current_user: user} do
    %{user: user, module: Factory.insert(:module, code: "<p>teaser</p>", vars: [], refs: [])}
  end

  test "Delete on a module a page uses names the page and leaves the module", %{conn: conn} = c do
    page = page!(c.user, c.module, "Front page")
    {:ok, view, _html} = live(conn, "/admin/config/content/modules")
    await_selector(view, ".list-row")

    render_hook(view, "describe_delete", %{"id" => to_string(c.module.id)})
    assert_reply(view, %{refused: true, html: html})
    assert html =~ ~s(href="/admin/pages/update/#{page.id}")
    assert html =~ "Front page"

    render_click(view, "delete_entry", %{"id" => to_string(c.module.id)})
    assert %{deleted_at: nil} = Repo.get!(Module, c.module.id)
  end

  test "Delete on a module only a page in the trash uses moves it to the trash", %{conn: conn} = c do
    page = page!(c.user, c.module, "Old page")
    {:ok, _} = Brando.Pages.delete_page(page.id, c.user)
    {:ok, view, _html} = live(conn, "/admin/config/content/modules")
    await_selector(view, ".list-row")

    render_hook(view, "describe_delete", %{"id" => to_string(c.module.id)})
    assert_reply(view, reply)
    refute Map.has_key?(reply, :refused)

    render_click(view, "delete_entry", %{"id" => to_string(c.module.id)})
    assert %{deleted_at: %DateTime{}} = Repo.get!(Module, c.module.id)
  end

  test "Delete on an unused module moves it to the trash", %{conn: conn} = c do
    {:ok, view, _html} = live(conn, "/admin/config/content/modules")
    await_selector(view, ".list-row")

    render_click(view, "delete_entry", %{"id" => to_string(c.module.id)})
    assert %{deleted_at: %DateTime{}} = Repo.get!(Module, c.module.id)
  end

  # A page whose one block uses `module`
  defp page!(user, module, title) do
    block = %{
      type: :module,
      module_id: module.id,
      source: "Elixir.Brando.Pages.Page.Blocks",
      uid: "block-#{System.unique_integer([:positive])}"
    }

    changeset =
      %Page{}
      |> Page.changeset(Factory.params_for(:page, title: title), user)
      |> Ecto.Changeset.put_assoc(:entry_blocks, [%{block: block}])
      |> Map.put(:action, :insert)

    {:ok, page} = Brando.Pages.create_page(changeset, user)
    page
  end
end
