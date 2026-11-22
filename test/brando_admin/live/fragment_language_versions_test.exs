defmodule BrandoAdmin.FragmentLanguageVersionsTest do
  # The form's language versions drawer for fragments, which keep no stored
  # identifiers: the versions linked to the fragment, and the fragments with
  # its keys in another language that are not. Both list only what the
  # editor may read.
  # Grouped, one at a time: the policy test takes the authorization lock
  use Brando.LiveCase, async: true, group: :shared_locks

  import Brando.Test.Users
  import Ecto.Query, only: [from: 2]

  alias Brando.AuthorizationTestResources.Snippet
  alias Brando.Pages.Fragment
  alias Brando.Repo
  alias BrandoAdmin.Components.Form.AlternatesDrawer

  defp drawer(view), do: with_target(view, cid_of(view, "#fragment_form-alternates-drawer"))

  defp linked?(a, b),
    do:
      Repo.aggregate(from(x in Fragment.Alternate, where: x.entry_id == ^a.id and x.linked_entry_id == ^b.id), :count) ==
        1

  test "lists the linked versions and the unlinked ones with the same keys, opens and links them", %{conn: conn} do
    norsk = Factory.insert(:fragment, title: "Bunn norsk", parent_key: "footer", key: "contact", language: :no)
    english = Factory.insert(:fragment, title: "Footer English", parent_key: "footer", key: "contact", language: :en)
    other = Factory.insert(:fragment, title: "Help English", parent_key: "footer", key: "help", language: :en)
    :ok = Fragment.Alternate.add(norsk.id, other.id)

    {conn, _user} = log_in_as(conn)
    {view, _html} = live_form(conn, "/admin/pages/fragments/update/#{norsk.id}", "fragment_form")

    linked = "#fragment_form-alternates-drawer .alternates-linked article[data-id='#{other.id}']"
    unlinked = "#fragment_form-alternates-drawer .alternates-unlinked article[data-id='#{english.id}']"

    assert has_element?(view, linked, "Help English")
    assert has_element?(view, unlinked, "Footer English")
    assert view |> element(unlinked) |> render() =~ "/admin/pages/fragments/update/#{english.id}"

    view |> element("#{unlinked} button[phx-click*=select_entry]") |> render_click()

    assert linked?(norsk, english) and linked?(english, norsk)
    assert has_element?(view, "#fragment_form-alternates-drawer .alternates-linked article[data-id='#{english.id}']")

    # Offered for linking: fragments in other languages
    view |> drawer() |> render_click("get_entries_identifiers", %{})
    refute has_element?(view, "#fragment_form-alternates-drawer .entries-identifiers article[data-id='#{english.id}']")
    third = Factory.insert(:fragment, title: "Third", parent_key: "x", key: "y", language: :en)
    view |> drawer() |> render_click("get_entries_identifiers", %{})
    view |> drawer() |> render_click("select_entry", %{"id" => third.id})
    assert linked?(norsk, third)
  end

  # Edge case 5
  describe "behind a record policy" do
    setup do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      :ok
    end

    defp snippet!(title, language, creator),
      do: Repo.insert!(%Snippet{title: title, key: "contact", language: language, creator_id: creator.id})

    test "an entry the editor may not read is not listed, nor that it exists" do
      editor =
        insert_user(
          permissions: ~w(brando.admin.access authorization.policy_snippets.read authorization.policy_snippets.update)
        )

      owner = insert_user()

      own = snippet!("Own Norwegian", :no, editor)
      readable = snippet!("Own English", :en, editor)
      hidden_linked = snippet!("Secret English", :en, owner)
      hidden_unlinked = snippet!("Hidden twin", :en, owner)
      :ok = Snippet.Alternate.add(own.id, readable.id)
      :ok = Snippet.Alternate.add(own.id, hidden_linked.id)

      html =
        render_component(AlternatesDrawer,
          id: "snippet-alternates",
          entry: own,
          current_user: editor,
          on_close: nil
        )

      assert html =~ "Own English"
      refute html =~ "Secret English"
      refute html =~ "Hidden twin"
      refute html =~ ~s(data-id="#{hidden_linked.id}")
      refute html =~ ~s(data-id="#{hidden_unlinked.id}")
    end
  end
end
