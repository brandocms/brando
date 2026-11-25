defmodule Brando.Pages.DeletePageFragmentsTest do
  # Deleting a page with fragments (#3621): they are moved or go with it, in
  # the delete's transaction, and are never left on the trashed page
  use Brando.ConnCase, async: true

  import Ecto.Query, only: [from: 2]

  alias Brando.Authorization.Boundary
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Fragment
  alias Brando.Pages.Page

  setup do
    put_test_env(:tenancy_mode, :none)
    %{user: Factory.insert(:random_user, role: :superuser)}
  end

  defp page!(user, attrs) do
    params = Map.merge(%{language: "en", template: "default.html", status: :published}, attrs)
    {:ok, page} = Pages.create_page(params, user)
    page
  end

  defp fragment!(user, page, key, attrs \\ %{}) do
    Factory.insert(
      :fragment,
      Map.merge(%{creator: user, page_id: page && page.id, parent_key: "partials", key: key}, attrs)
    )
  end

  defp reload(%Fragment{id: id}), do: Repo.get!(Fragment, id)
  defp reload(%Page{id: id}), do: Repo.get!(Page, id)

  describe "delete_page/2, with no choice" do
    test "moves the fragments to the parent page", %{user: user} do
      parent = page!(user, %{title: "Parent", uri: "parent"})
      page = page!(user, %{title: "Child", uri: "parent/child", parent_id: parent.id})
      header = fragment!(user, page, "header")
      footer = fragment!(user, page, "footer")

      assert {:ok, _} = Pages.delete_page(page.id, user)

      assert reload(page).deleted_at
      assert %{page_id: page_id, deleted_at: nil} = reload(header)
      assert page_id == parent.id
      assert reload(footer).page_id == parent.id

      # Recorded as the deleting editor's change of the fragment
      assert [%{action: :updated, user_id: user_id}] = Brando.Activity.for_entry(Fragment, header.id)
      assert user_id == user.id
    end

    test "passes over a trashed parent to the nearest live ancestor", %{user: user} do
      top = page!(user, %{title: "Top", uri: "top"})
      middle = page!(user, %{title: "Middle", uri: "top/middle", parent_id: top.id})
      page = page!(user, %{title: "Bottom", uri: "top/middle/bottom", parent_id: middle.id})
      header = fragment!(user, page, "header")

      {:ok, _} = Pages.delete_page(middle.id, user, fragments: :delete)
      assert {:ok, _} = Pages.delete_page(page.id, user)

      assert reload(header).page_id == top.id
    end

    test "a top-level page's fragments go to the homepage in its language", %{user: user} do
      home = page!(user, %{title: "Home", uri: "index", is_homepage: true})
      _other_home = page!(user, %{title: "Hjem", uri: "index-no", language: "no", is_homepage: true})
      page = page!(user, %{title: "Campaign", uri: "campaign"})
      header = fragment!(user, page, "header")

      assert Pages.fragment_target(page).id == home.id
      assert {:ok, _} = Pages.delete_page(page.id, user)

      assert reload(header).page_id == home.id
    end

    test "with no page to go to, they are kept on the site with no page", %{user: user} do
      page = page!(user, %{title: "Hjem", uri: "index-no", language: "no", is_homepage: true})
      _other_language = page!(user, %{title: "Home", uri: "index", is_homepage: true})
      footer = fragment!(user, page, "footer", %{language: :no})

      assert Pages.fragment_target(page) == nil
      assert {:ok, _} = Pages.delete_page(page.id, user)

      assert %{page_id: nil, deleted_at: nil} = reload(footer)
      assert [%{id: id}] = Pages.list_fragments_without_page()
      assert id == footer.id
    end

    test "leaves a fragment already in the trash where it is", %{user: user} do
      parent = page!(user, %{title: "Parent", uri: "parent"})
      page = page!(user, %{title: "Child", uri: "parent/child", parent_id: parent.id})
      trashed = fragment!(user, page, "old")
      {:ok, _} = Pages.delete_fragment(trashed.id, user)

      assert {:ok, _} = Pages.delete_page(page.id, user)

      assert %{page_id: page_id, deleted_at: %DateTime{}} = reload(trashed)
      assert page_id == page.id
    end
  end

  describe "editors with a fragment open" do
    test "are told it moved, or went to the trash, once the delete commits", %{user: user} do
      parent = page!(user, %{title: "Parent", uri: "parent"})
      page = page!(user, %{title: "Child", uri: "parent/child", parent_id: parent.id})
      other = page!(user, %{title: "Other", uri: "other"})
      %{id: header_id} = fragment!(user, page, "header")
      %{id: footer_id} = fragment!(user, other, "footer")
      Phoenix.PubSub.subscribe(Brando.pubsub(), Brando.Tenant.Topic.scoped("brando:mutations:Brando.Pages.Fragment"))

      {:ok, _} = Pages.delete_page(page.id, user)
      assert_receive {:mutation, Fragment, %{id: ^header_id, page_id: page_id}, :updated}
      assert page_id == parent.id

      {:ok, _} = Pages.delete_page(other.id, user, fragments: :delete)
      assert_receive {:mutation, Fragment, %{id: ^footer_id, deleted_at: %DateTime{}}, :deleted}
    end
  end

  test "a page already in the trash is not deleted again", %{user: user} do
    page = page!(user, %{title: "Page", uri: "page"})
    header = fragment!(user, page, "header")
    {:ok, deleted} = Pages.delete_page(page.id, user, fragments: :delete)

    assert {:error, {:page, :not_found}} = Pages.delete_page(page.id, user)
    assert reload(page).deleted_at == deleted.deleted_at
    assert reload(header).deleted_at == deleted.deleted_at
  end

  describe "delete_page/3, fragments: {:move, page_id}" do
    test "moves them to the page given", %{user: user} do
      parent = page!(user, %{title: "Parent", uri: "parent"})
      page = page!(user, %{title: "Child", uri: "parent/child", parent_id: parent.id})
      target = page!(user, %{title: "Elsewhere", uri: "elsewhere"})
      header = fragment!(user, page, "header")

      assert {:ok, _} = Pages.delete_page(page.id, user, fragments: {:move, target.id})

      assert reload(header).page_id == target.id
    end

    test "{:move, nil} keeps them with no page", %{user: user} do
      parent = page!(user, %{title: "Parent", uri: "parent"})
      page = page!(user, %{title: "Child", uri: "parent/child", parent_id: parent.id})
      header = fragment!(user, page, "header")

      assert {:ok, _} = Pages.delete_page(page.id, user, fragments: {:move, nil})

      assert %{page_id: nil, deleted_at: nil} = reload(header)
    end

    test "a trashed page, a missing one or the page itself is refused, and nothing is deleted", %{user: user} do
      page = page!(user, %{title: "Page", uri: "page"})
      trashed = page!(user, %{title: "Trashed", uri: "trashed"})
      {:ok, _} = Pages.delete_page(trashed.id, user)
      header = fragment!(user, page, "header")

      for target <- [trashed.id, page.id, -1] do
        assert {:error, {:fragments, :target_not_found}} =
                 Pages.delete_page(page.id, user, fragments: {:move, target})

        assert is_nil(reload(page).deleted_at)
        assert reload(header).page_id == page.id
      end
    end

    test "an unknown choice is refused before anything happens", %{user: user} do
      page = page!(user, %{title: "Page", uri: "page"})

      assert {:error, {:fragments, :invalid_choice}} = Pages.delete_page(page.id, user, fragments: :keep)
      assert is_nil(reload(page).deleted_at)
    end
  end

  describe "delete_page/3, fragments: :delete" do
    test "trashes them with the page, and restoring the page brings them back", %{user: user} do
      parent = page!(user, %{title: "Parent", uri: "parent"})
      page = page!(user, %{title: "Child", uri: "parent/child", parent_id: parent.id})
      header = fragment!(user, page, "header")
      footer = fragment!(user, page, "footer")
      trashed_before = fragment!(user, page, "old")
      {:ok, _} = Pages.delete_fragment(trashed_before.id, user)
      # deleted_at is stored to the second: trashed a minute earlier
      trashed_before_at = DateTime.add(reload(trashed_before).deleted_at, -60)
      Repo.update_all(from(f in Fragment, where: f.id == ^trashed_before.id), set: [deleted_at: trashed_before_at])

      assert {:ok, deleted} = Pages.delete_page(page.id, user, fragments: :delete)

      assert reload(header).deleted_at == deleted.deleted_at
      assert reload(footer).deleted_at == deleted.deleted_at
      assert reload(header).page_id == page.id
      assert Pages.get_fragments("partials", "en") == %{}

      assert {:ok, _} = Boundary.restore(user, reload(page))

      assert %{deleted_at: nil, page_id: page_id} = reload(header)
      assert page_id == page.id
      assert is_nil(reload(footer).deleted_at)
      # Trashed on its own, before the page: it stays in the trash
      assert reload(trashed_before).deleted_at == trashed_before_at
    end

    test "a fragment trashed on its own in the same second as the page stays in the trash", %{user: user} do
      # deleted_at is stored to the second: tried until both fall in one
      {page, alone, with_page} =
        Enum.find_value(1..5, fn n ->
          page = page!(user, %{title: "Page #{n}", uri: "page-#{n}"})
          alone = fragment!(user, page, "alone-#{n}")
          with_page = fragment!(user, page, "with-#{n}")
          at = Brando.SoftDelete.Repo.utc_now()
          Repo.update_all(from(f in Fragment, where: f.id == ^alone.id), set: [deleted_at: at])
          {:ok, deleted} = Pages.delete_page(page.id, user, fragments: :delete)
          if deleted.deleted_at == at, do: {deleted, alone, with_page}
        end)

      assert reload(alone).deleted_at == DateTime.add(page.deleted_at, -1)
      assert reload(with_page).deleted_at == page.deleted_at

      assert {:ok, _} = Boundary.restore(user, reload(page))

      assert reload(alone).deleted_at
      assert is_nil(reload(with_page).deleted_at)
    end

    test "a fragment restored on its own, while its page is in the trash, is listed without a page", %{user: user} do
      page = page!(user, %{title: "Page", uri: "page"})
      header = fragment!(user, page, "header")
      {:ok, _} = Pages.delete_page(page.id, user, fragments: :delete)

      assert {:ok, _} = Boundary.restore(user, reload(header))

      assert [%{id: id}] = Pages.list_fragments_without_page()
      assert id == header.id
    end

    test "the trash's purge removes them with the page", %{user: user} do
      page = page!(user, %{title: "Page", uri: "page"})
      header = fragment!(user, page, "header")
      {:ok, _} = Pages.delete_page(page.id, user, fragments: :delete)

      old = DateTime.add(DateTime.truncate(DateTime.utc_now(), :second), -31 * 86_400)
      Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [deleted_at: old])
      Repo.update_all(from(f in Fragment, where: f.id == ^header.id), set: [deleted_at: old])

      refute Enum.any?(Brando.SoftDelete.Query.clean_up_soft_deletions(), &match?({:error, _}, &1))

      refute Repo.get(Page, page.id)
      refute Repo.get(Fragment, header.id)
    end
  end

  describe "fragments without a page" do
    test "lists the live fragments whose page is trashed, gone or never set, in no other", %{user: user} do
      page = page!(user, %{title: "Page", uri: "page"})
      live = page!(user, %{title: "Live", uri: "live"})
      _attached = fragment!(user, live, "attached")
      no_page = fragment!(user, nil, "no-page")
      on_trashed = fragment!(user, page, "on-trashed")
      trashed_fragment = fragment!(user, nil, "trashed")
      {:ok, _} = Pages.delete_fragment(trashed_fragment.id, user)
      # As a page trashed before #3621 left them
      Repo.update_all(from(p in Page, where: p.id == ^page.id), set: [deleted_at: DateTime.utc_now()])

      ids = Enum.map(Pages.list_fragments_without_page(), & &1.id)

      assert Enum.sort(ids) == Enum.sort([no_page.id, on_trashed.id])
      assert Pages.list_fragments_without_page("no") == []
      assert length(Pages.list_fragments_without_page(:en)) == 2
    end
  end

  describe "the delete dialog" do
    alias BrandoAdmin.LiveView.Listing.DeleteDescription

    test "a page with fragments lists them and asks where they go, the parent preselected", %{user: user} do
      parent = page!(user, %{title: "Parent", uri: "parent"})
      page = page!(user, %{title: "Child", uri: "parent/child", parent_id: parent.id})
      _ = fragment!(user, page, "header", %{title: "Header <b>"})
      _ = fragment!(user, page, "footer", %{title: nil})
      trashed = fragment!(user, page, "old", %{title: "Old"})
      {:ok, _} = Pages.delete_fragment(trashed.id, user)

      %{html: html, choice: choice} = DeleteDescription.describe(Page, page)

      assert html =~ "Header &lt;b&gt;"
      assert html =~ "partials/footer"
      assert html =~ "[EN]"
      refute html =~ "Old"

      assert %{name: "fragments", options: [move, delete]} = choice
      assert %{value: "move", checked: true, select: %{name: "fragments_page", selected: selected}} = move
      assert selected == to_string(parent.id)
      assert %{value: "delete", checked: false} = delete

      values = Enum.map(move.select.options, & &1.value)
      assert "" in values
      assert to_string(parent.id) in values
      refute to_string(page.id) in values
    end

    test "a page without fragments has today's plain confirmation", %{user: user} do
      page = page!(user, %{title: "Plain", uri: "plain"})

      refute Map.has_key?(DeleteDescription.describe(Page, page), :choice)
    end
  end
end
