defmodule BrandoAdmin.DashboardTest do
  use Brando.ConnCase

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.Content.Identifier
  alias Brando.Factory

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    owner = Factory.insert(:random_user, role: :superuser)
    user = Factory.insert(:random_user, role: :user)
    {:ok, _} = Migration.run()
    page = Factory.insert(:page, title: "Private draft", status: :draft)

    Repo.insert!(%Identifier{
      schema: Brando.Pages.Page,
      entry_id: page.id,
      title: page.title,
      status: :draft,
      language: :en,
      updated_at: DateTime.utc_now(:second)
    })

    %{scope: Scope.standalone(owner), user: user, page: page}
  end

  test "a user without content access sees neither titles nor shortcuts", c do
    overview = BrandoAdmin.Dashboard.load(c.user)
    assert overview.recent == []
    assert overview.drafts == []
    assert overview.shortcuts == []
    assert Boundary.current_scope() == nil
  end

  test "read-only access shows content without an edit link or editable draft", c do
    grant(c, ~w(brando.admin.access brando.pages.read))
    overview = BrandoAdmin.Dashboard.load(c.user)
    assert [%{title: "Private draft", path: nil}] = overview.recent
    assert overview.drafts == []
    assert [%{path: "/admin/pages"}] = overview.shortcuts
  end

  test "drafts require edit access and disappear after permissions are revoked", c do
    group = grant(c, ~w(brando.admin.access brando.pages.read brando.pages.update))
    assert [%{path: path}] = BrandoAdmin.Dashboard.load(c.user).drafts
    assert path == "/admin/pages/update/#{c.page.id}"
    {:ok, :ok} = Groups.remove_member(c.scope, group.id, c.user.id)
    assert BrandoAdmin.Dashboard.load(c.user).recent == []
    assert BrandoAdmin.Dashboard.load(c.user).drafts == []
  end

  test "deleted source records are excluded even when their identifier remains", c do
    grant(c, ~w(brando.admin.access brando.pages.read brando.pages.update))
    Repo.update!(Ecto.Changeset.change(c.page, deleted_at: DateTime.utc_now(:second)))
    assert BrandoAdmin.Dashboard.load(c.user).recent == []
  end

  test "the site's own menu entries come first, without repeating the general ones", c do
    grant(c, ~w(brando.admin.access brando.pages.read brando.images.read))
    shortcuts = BrandoAdmin.Dashboard.load(c.user).shortcuts
    paths = Enum.map(shortcuts, &URI.parse(&1.path).path)

    # The integration app's menu has a single entry: Pages.
    assert hd(paths) == "/admin/pages"
    assert paths == Enum.uniq(paths)
    assert "/admin/assets/images" in paths
    # No global sets, no menus: no shortcuts to empty screens.
    refute "/admin/globals" in paths
  end

  defp grant(c, keys) do
    {:ok, group} = Groups.create(c.scope, %{name: "Dashboard access"}, keys)
    {:ok, :ok} = Groups.add_member(c.scope, group.id, c.user.id)
    group
  end
end
