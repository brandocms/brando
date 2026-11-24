defmodule Brando.SoftDelete.RestoreAddressTest do
  # A restore asks for a free address the way a save of the type does, in the
  # same scope (a page's address is unique per language), and for a draft too
  # (#3941). One it can't give, or one taken all the same, is an error and the
  # entry stays in the trash. So is a row gone or restored since it was read.
  use Brando.ConnCase

  alias Brando.Authorization.{Boundary, Migration}
  alias Brando.Factory
  alias Brando.Pages
  alias Brando.Pages.Page

  setup do
    put_test_env(:tenancy_mode, :none)
    Boundary.put_scope(nil)
    on_exit(fn -> Boundary.put_scope(nil) end)

    %{user: Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})}
  end

  for mode <- [:legacy, :groups] do
    describe "with #{mode} authorization" do
      @describetag mode: mode

      setup %{mode: mode} do
        put_test_env(:authorization_mode, mode)
        if mode == :groups, do: {:ok, _} = Migration.run()
        :ok
      end

      test "a draft whose address was taken comes back a draft, with a suffix", %{user: user} do
        draft = trashed!(user, %{uri: "about", status: :draft})
        page!(user, %{uri: "about"})

        assert {:ok, %Page{uri: "about-1", status: :draft, deleted_at: nil}} = Boundary.restore(user, reload(draft))
      end
    end
  end

  for status <- [:draft, :published] do
    describe "a #{status} page" do
      @describetag status: status

      test "takes a suffix when its address is held in its language and another", %{user: user, status: status} do
        page = trashed!(user, %{uri: "about", status: status})
        page!(user, %{uri: "about", language: "en"})
        page!(user, %{uri: "about", language: "no"})

        assert {:ok, %Page{uri: "about-1"}} = Boundary.restore(user, reload(page))
      end

      test "keeps its address when only another language holds it", %{user: user, status: status} do
        page = trashed!(user, %{uri: "about", status: status})
        page!(user, %{uri: "about", language: "no"})

        assert {:ok, %Page{uri: "about"}} = Boundary.restore(user, reload(page))
      end
    end
  end

  test "with its address and the next 29 taken, it is refused and stays in the trash", %{user: user} do
    draft = trashed!(user, %{uri: "about", status: :draft})
    for uri <- ["about" | Enum.map(1..29, &"about-#{&1}")], do: page!(user, %{uri: uri})

    assert {:error, {:taken, :uri}} = Boundary.restore(user, reload(draft))
    assert reload(draft).deleted_at
  end

  test "an address taken all the same is an error, and the page stays in the trash", %{user: user} do
    draft = trashed!(user, %{uri: "about", status: :draft})
    # Trashed without freeing its address: the check passes over the trash, the index does not
    held = page!(user, %{uri: "about"})
    Brando.Repo.soft_delete_all(from(p in Page, where: p.id == ^held.id))

    assert {:error, {:taken, :uri}} = Boundary.restore(user, reload(draft))
    assert reload(draft).deleted_at
  end

  test "a page deleted for good since it was read is not restored", %{user: user} do
    page = trashed!(user, %{uri: "about"})
    assert :ok = Brando.SoftDelete.Query.purge_entry(Page, page.id, page.deleted_at, user)

    assert {:error, :not_in_trash} = Boundary.restore(user, page)
  end

  test "a page restored since it was read is not restored again", %{user: user} do
    page = trashed!(user, %{uri: "about"})
    assert {:ok, _} = Boundary.restore(user, reload(page))

    assert {:error, :not_in_trash} = Boundary.restore(user, reload(page))
  end

  defp trashed!(user, attrs) do
    page = page!(user, attrs)
    {:ok, page} = Pages.delete_page(page.id, user)
    page
  end

  defp page!(user, attrs) do
    params = Map.merge(%{title: "Page", language: "en", template: "default.html", status: :published}, attrs)
    {:ok, page} = Pages.create_page(params, user)
    page
  end

  defp reload(%Page{id: id}), do: Repo.get!(Page, id)
end
