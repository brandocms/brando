defmodule BrandoAdmin.UserListActionsTest do
  # Disabling and enabling a user from the listing: on behalf of the signed-in
  # user, and only with permission to update users.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Activity.Event
  alias Brando.Authorization.Migration
  alias Brando.Factory
  alias Brando.Users.UserConfig
  alias BrandoIntegration.Repo

  defp user(attrs \\ []), do: Factory.insert(:random_user, Keyword.merge([role: :editor, config: %UserConfig{}], attrs))

  test "disabling and enabling act as the signed-in user", %{conn: conn, current_user: admin} do
    target = user()
    {:ok, view, _html} = live(conn, "/admin/users")

    render_click(view, "disable_user", %{"id" => to_string(target.id)})
    refute Repo.get!(Brando.Users.User, target.id).active

    render_click(view, "enable_user", %{"id" => to_string(target.id)})
    assert Repo.get!(Brando.Users.User, target.id).active

    # Recorded as the admin's doing, not the target's
    user_ids =
      Repo.all(
        from e in Event, where: e.schema == "Elixir.Brando.Users.User" and e.entry_id == ^target.id, select: e.user_id
      )

    assert user_ids != []
    assert Enum.all?(user_ids, &(&1 == admin.id))
  end

  describe "with groups authorization" do
    setup do
      put_test_env(:authorization_mode, :groups)
      put_test_env(:tenancy_mode, :none)
      :ok
    end

    test "enabling needs permission to update users, as disabling does", %{current_user: admin} do
      reader = user(role: :admin, config: %UserConfig{reset_password_on_first_login: false})
      target = user(active: false)
      {:ok, _} = Migration.run()

      # A group that may see users but not change them
      scope = Brando.Authorization.Scope.standalone(admin)

      {:ok, group} =
        Brando.Authorization.Groups.create(scope, %{name: "User readers"}, ["brando.admin.access", "brando.users.read"])

      Repo.delete_all(from m in Brando.Authorization.Membership, where: m.user_id == ^reader.id)
      {:ok, _} = Brando.Authorization.Groups.add_member(scope, group.id, reader.id)

      conn = log_in_user(Phoenix.ConnTest.build_conn(), reader)
      {:ok, view, _html} = live(conn, "/admin/users")

      render_click(view, "enable_user", %{"id" => to_string(target.id)})
      refute Repo.get!(Brando.Users.User, target.id).active

      render_click(view, "disable_user", %{"id" => to_string(admin.id)})
      assert Repo.get!(Brando.Users.User, admin.id).active
    end
  end
end
