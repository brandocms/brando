defmodule BrandoAdmin.AlternatesAuthorizationTest do
  # With group authorization, linking and unlinking translations (alternates)
  # takes `:update` on both entries, from the listing row and from the entry
  # form's alternates drawer alike: their events go to LiveComponents, which
  # the view's event check never sees. The schema is the entry's own.
  use Brando.LiveCase

  import Brando.Test.Users
  import Ecto.Query

  alias Brando.Pages.Page
  alias Brando.Repo

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)

    norsk = Factory.insert(:page, title: "Norsk", language: :no)
    english = Factory.insert(:page, title: "English", language: :en)
    :ok = Page.Alternate.add(norsk.id, english.id)

    %{norsk: norsk, english: english, deutsch: Factory.insert(:page, title: "British", language: :en)}
  end

  defp links, do: Repo.aggregate(from(a in Page.Alternate), :count)

  defp linked?(a, b),
    do: Repo.aggregate(from(x in Page.Alternate, where: x.entry_id == ^a.id and x.linked_entry_id == ^b.id), :count) > 0

  defp row(view, page), do: with_target(view, cid_of(view, "#entry-#{page.id}-alternates"))

  describe "listing row" do
    test "reading alone does not unlink, nor offers to", %{conn: conn} = c do
      {conn, _user} = log_in_as(conn, permissions: ~w(brando.pages.read))
      {:ok, view, _html} = live(conn, "/admin/pages")

      assert has_element?(view, "#entry-#{c.english.id}-alternates")
      refute has_element?(view, "#entry-#{c.english.id}-alternates button[phx-click*=remove_entry]")

      view |> row(c.english) |> render_click("remove_entry", %{"id" => c.norsk.id})
      assert links() == 2
    end

    test "updating unlinks", %{conn: conn} = c do
      {conn, _user} = log_in_as(conn, permissions: ~w(brando.pages.read brando.pages.update))
      {:ok, view, _html} = live(conn, "/admin/pages")

      view |> element("#entry-#{c.english.id}-alternates button[phx-click*=remove_entry]") |> render_click()
      assert links() == 0
    end

    test "a sub-page's alternate is unlinked from the sub-page", %{conn: conn} = c do
      child = Factory.insert(:page, title: "Child", language: :en, parent_id: c.english.id)
      :ok = Page.Alternate.add(child.id, c.deutsch.id)
      {conn, _user} = log_in_as(conn, permissions: ~w(brando.pages.read brando.pages.update))
      {:ok, view, _html} = live(conn, "/admin/pages")

      view |> row(c.english) |> render_click("toggle_children", %{"fields" => ["children"]})
      view |> element("#entry-#{child.id}-alternates button[phx-click*=remove_entry]") |> render_click()

      refute linked?(child, c.deutsch)
      assert linked?(c.english, c.norsk)
    end

    test "the schema is the row's, not one the client names", %{conn: conn} = c do
      {conn, _user} = log_in_as(conn, permissions: ~w(brando.pages.read brando.pages.update))
      {:ok, view, _html} = live(conn, "/admin/pages")
      name = "Elixir.NoSuch#{System.unique_integer([:positive])}"

      view
      |> row(c.english)
      |> render_click("update_entry", %{"entry_id" => c.norsk.id, "parent_id" => c.english.id, "schema" => name})

      assert_redirect(view, "/admin/pages/update/#{c.norsk.id}")
      assert_raise ArgumentError, fn -> String.to_existing_atom(name) end
    end
  end

  describe "the context" do
    test "linking and unlinking take update on both entries", c do
      reader = insert_user(permissions: ~w(brando.admin.access brando.pages.read))
      editor = insert_user(permissions: ~w(brando.admin.access brando.pages.read brando.pages.update))

      assert {:error, :forbidden} = Page.Alternate.add(c.deutsch.id, c.norsk.id, reader)
      assert {:error, :forbidden} = Page.Alternate.delete(c.english.id, c.norsk.id, reader)
      assert links() == 2

      assert :ok = Page.Alternate.add(c.deutsch.id, c.norsk.id, editor)
      assert linked?(c.deutsch, c.norsk)
      assert {2, _} = Page.Alternate.delete(c.english.id, c.norsk.id, editor)
      refute linked?(c.english, c.norsk)
    end
  end

  describe "entry form drawer" do
    defp drawer(view), do: with_target(view, cid_of(view, "#page_form-alternates-drawer"))

    test "links only entries it offered", %{conn: conn} = c do
      Brando.Content.create_identifier(Page, c.deutsch)
      {conn, _user} = log_in_as(conn, permissions: ~w(brando.pages.read brando.pages.update))
      {view, _html} = live_form(conn, "/admin/pages/update/#{c.norsk.id}")

      # Not offered yet: the list of entries to link is empty
      view |> drawer() |> render_click("select_entry", %{"id" => c.deutsch.id})
      refute linked?(c.deutsch, c.norsk)

      view |> drawer() |> render_click("get_entries_identifiers", %{})
      view |> drawer() |> render_click("select_entry", %{"id" => c.deutsch.id})
      assert linked?(c.deutsch, c.norsk)
    end
  end
end
