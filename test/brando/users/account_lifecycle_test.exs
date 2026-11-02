defmodule Brando.Users.AccountLifecycleTest do
  # What a removed account keeps out of reach: bringing it back takes the
  # authority removing it takes, in both modes; a transfer moves content only,
  # never the account's connections or private working data; the change
  # password screen counts wrong guesses; and a rejected form logs no password.
  use Brando.LiveCase

  import Brando.MCPHelpers
  import Ecto.Query, only: [from: 2]
  import ExUnit.CaptureLog

  alias Brando.Authorization.{Boundary, Groups, Migration, Scope}
  alias Brando.ListingViews.Default
  alias Brando.ListingViews.View
  alias Brando.MCP
  alias Brando.MCP.AuthorizationCode
  alias Brando.MCP.Grant
  alias Brando.Test.Users, as: TestUsers
  alias Brando.Users
  alias Brando.Users.SecurityEvent
  alias Brando.Users.Throttle
  alias Brando.Users.User
  alias Phoenix.Socket.Broadcast

  defp removed(user, how, by) do
    case how do
      :deleted -> {:ok, _} = Users.delete_user(user.id, by)
      :deactivated -> {:ok, _} = Users.set_active(user.id, false, by)
    end

    Repo.get!(User, user.id)
  end

  defp assert_refused_bringing_back(view, deleted, deactivated, actor) do
    render_hook(view, "undelete_entry", %{"id" => to_string(deleted.id)})
    assert Repo.get!(User, deleted.id).deleted_at

    render_hook(view, "enable_user", %{"id" => to_string(deactivated.id)})
    refute Repo.get!(User, deactivated.id).active

    assert {:error, :forbidden} = Boundary.restore(actor, deleted)
    assert Repo.get!(User, deleted.id).deleted_at

    assert {:error, _} = Users.set_active(deactivated.id, true, actor)
    refute Repo.get!(User, deactivated.id).active
  end

  describe "bringing back a superuser, legacy mode" do
    setup %{current_user: superuser} do
      %{
        deleted: removed(TestUsers.insert_user(role: :superuser), :deleted, superuser),
        deactivated: removed(TestUsers.insert_user(role: :superuser), :deactivated, superuser)
      }
    end

    for role <- [:editor, :admin] do
      test "#{role} is refused", %{deleted: deleted, deactivated: deactivated} do
        actor = TestUsers.insert_user(role: unquote(role))
        {:ok, view, _} = live(log_in_user(build_conn(), actor), "/admin/users")
        assert_refused_bringing_back(view, deleted, deactivated, actor)
      end
    end

    test "a changeset built outside the schema is refused too", %{deleted: deleted, deactivated: deactivated} do
      admin = TestUsers.insert_user(role: :admin)

      assert {:error, :forbidden} = Users.update_user(Ecto.Changeset.change(deactivated, active: true), admin)
      assert {:error, :forbidden} = Users.update_user(Ecto.Changeset.change(deleted, deleted_at: nil), admin)
    end

    test "a superuser brings them back", %{current_user: superuser, deleted: deleted, deactivated: deactivated} do
      assert {:ok, %{deleted_at: nil}} = Boundary.restore(superuser, deleted)
      assert {:ok, %{active: true}} = Users.set_active(deactivated.id, true, superuser)
    end

    test "the screen says so when it refuses", %{deleted: deleted} do
      editor = TestUsers.insert_user(role: :editor)
      {:ok, view, _} = live(log_in_user(build_conn(), editor), "/admin/users")
      Brando.endpoint().subscribe("user:#{editor.id}")

      render_hook(view, "undelete_entry", %{"id" => to_string(deleted.id)})

      assert_receive %Broadcast{event: "toast", payload: %{payload: "Error undeleting" <> _}}, 2_000
      refute_received %Broadcast{event: "toast", payload: %{payload: "User undeleted"}}
    end

    test "an account below a superuser comes back as before", %{current_user: superuser} do
      editor = TestUsers.insert_user(role: :editor)
      admin = removed(TestUsers.insert_user(role: :admin), :deleted, superuser)
      other = removed(TestUsers.insert_user(role: :editor), :deactivated, superuser)

      assert {:ok, %{deleted_at: nil}} = Boundary.restore(editor, admin)
      assert {:ok, %{active: true}} = Users.set_active(other.id, true, editor)
    end
  end

  describe "bringing back a superuser, groups mode" do
    setup %{current_user: owner} do
      put_test_env(:authorization_mode, :groups)
      Boundary.put_scope(nil)
      on_exit(fn -> Boundary.put_scope(nil) end)

      # Superusers by role become members of the Superuser group
      deleted_user = TestUsers.insert_user(role: :superuser)
      deactivated_user = TestUsers.insert_user(role: :superuser)
      manager = TestUsers.insert_user(role: :editor)
      {:ok, _} = Migration.run()

      scope = Scope.standalone(owner)

      {:ok, group} =
        Groups.create(scope, %{name: "Account managers"}, [
          "brando.admin.access",
          "brando.users.read",
          "brando.users.update",
          "brando.users.delete",
          "brando.users.restore"
        ])

      {:ok, _} = Groups.add_member(scope, group.id, manager.id)

      %{
        manager: manager,
        deleted: removed(deleted_user, :deleted, owner),
        deactivated: removed(deactivated_user, :deactivated, owner)
      }
    end

    test "a holder of the restore grant is refused", %{manager: manager, deleted: deleted, deactivated: deactivated} do
      {:ok, view, _} = live(log_in_user(build_conn(), manager), "/admin/users")
      assert_refused_bringing_back(view, deleted, deactivated, manager)
    end

    test "other writes to a removed superuser are refused too", %{manager: manager, deactivated: deactivated} do
      assert {:error, _} = Users.update_user(deactivated.id, %{name: "Renamed"}, manager)
      assert Repo.get!(User, deactivated.id).name == deactivated.name
    end

    test "a superuser brings them back", %{current_user: owner, deleted: deleted, deactivated: deactivated} do
      assert {:ok, %{deleted_at: nil}} = Boundary.restore(owner, deleted)
      assert {:ok, %{active: true}} = Users.set_active(deactivated.id, true, owner)
      assert Boundary.superuser?(deleted)
    end

    test "an account outside the Superuser group comes back with the grant", c do
      other = removed(TestUsers.insert_user(role: :editor), :deleted, c.current_user)
      assert {:ok, %{deleted_at: nil}} = Boundary.restore(c.manager, other)
    end
  end

  describe "a delete with transfer and MCP" do
    setup %{current_user: source} do
      setup_fetcher()
      enable_two_factor(source)
      recipient = enable_two_factor(TestUsers.insert_user(role: :superuser))
      %{tenant: switch!(MCP.tenant(nil, nil)), recipient: recipient, deleter: TestUsers.insert_user(role: :superuser)}
    end

    test "ends the connection rather than handing it to the recipient", c do
      tokens = connect!(c.conn, c.tenant)
      assert rpc(c.tenant, tokens["access_token"], "ping").status == 200

      assert {:ok, _} = Users.delete_user_with_transfer(c.current_user.id, c.recipient.id, c.deleter)

      assert %Grant{user_id: user_id, revoked_reason: "account_deleted"} = Repo.one!(Grant)
      assert user_id == c.current_user.id
      refute Repo.exists?(from g in Grant, where: g.user_id == ^c.recipient.id)
      assert rpc(c.tenant, tokens["access_token"], "ping").status == 401

      refreshed =
        oauth_post(c.tenant, "token", %{
          "grant_type" => "refresh_token",
          "refresh_token" => tokens["refresh_token"],
          "client_id" => client_id()
        })

      assert json_response(refreshed, 400)["error"] == "invalid_grant"
    end

    test "ends a pending authorization code", c do
      {verifier, challenge} = pkce()
      %{"code" => code} = approve!(c.conn, authorize_params(c.tenant, challenge))

      assert {:ok, _} = Users.delete_user_with_transfer(c.current_user.id, c.recipient.id, c.deleter)

      assert %AuthorizationCode{used_at: %DateTime{}} = Repo.one!(AuthorizationCode)
      assert json_response(exchange(c.tenant, code, verifier), 400)["error"] == "invalid_grant"
      refute Repo.exists?(Grant)
    end

    test "a pending code does not outlast the account's restoration", c do
      {verifier, challenge} = pkce()
      %{"code" => code} = approve!(c.conn, authorize_params(c.tenant, challenge))

      assert {:ok, deleted} = Users.delete_user(c.current_user.id, c.deleter)
      assert {:ok, _} = Boundary.restore(c.deleter, deleted)

      assert json_response(exchange(c.tenant, code, verifier), 400)["error"] == "invalid_grant"
      refute Repo.exists?(Grant)
    end

    test "a transfer alone leaves the connection with its owner", c do
      connect!(c.conn, c.tenant)

      assert {:ok, _} = Users.transfer_user_content(c.current_user.id, c.recipient.id)

      assert %Grant{user_id: user_id, revoked_at: nil} = Repo.one!(Grant)
      assert user_id == c.current_user.id
    end

    test "the dialog does not count it as content", c do
      connect!(c.conn, c.tenant)
      tables = c.current_user.id |> Users.get_user_content_summary() |> Enum.map(& &1.table)
      refute Enum.any?(tables, &String.starts_with?(&1, "mcp_"))
    end
  end

  describe "a transfer and what is personal" do
    setup do
      %{source: TestUsers.insert_user(role: :editor), recipient: TestUsers.insert_user(role: :admin)}
    end

    defp assert_stays(source, recipient, table, column) do
      assert count(table, column, source.id) > 0
      refute Enum.any?(Users.get_user_content_summary(source.id), &(&1.table == table))

      assert {:ok, _} = Users.transfer_user_content(source.id, recipient.id)

      assert count(table, column, recipient.id) == 0
      assert count(table, column, source.id) > 0
    end

    defp count(table, column, id) do
      %{rows: [[count]]} = Repo.query!("SELECT count(*) FROM #{table} WHERE #{column} = $1", [id])
      count
    end

    test "assistant conversations stay with the account", %{source: source, recipient: recipient} do
      {:ok, conversation} = Brando.AI.Agent.start_conversation(source)

      assert_stays(source, recipient, "ai_conversations", "actor_id")

      assert Brando.AI.Agent.list_conversations(recipient) == []
      assert {:error, _} = Brando.AI.Agent.get_conversation(conversation.id, recipient)
    end

    test "recovery drafts stay with the account", %{source: source, recipient: recipient} do
      identity = Brando.Drafts.identity(Brando.Pages.Page, 1, source.id)
      {:ok, _} = Brando.Drafts.write(identity, Ecto.UUID.generate(), 1, %{"title" => "Unsaved"}, "base", 1)

      assert_stays(source, recipient, "entry_drafts", "owner_id")

      assert Brando.Drafts.list(%{identity | owner_id: recipient.id}) == []
    end

    # A queued build runs on the authority of who requested it (`Brando.Worker.SSGBuild`)
    test "a static build stays with the account", %{source: source, recipient: recipient} do
      {:ok, site} =
        Brando.Tenant.Registry.create_site(%{
          name: "Static",
          key: "static-#{System.unique_integer([:positive])}",
          languages: ["en"],
          default_language: "en",
          status: :active,
          delivery_mode: :static
        })

      Repo.insert!(%Brando.SSG.Build{
        site_id: site.id,
        creator_id: source.id,
        version: "v1",
        build_number: 1,
        environment_name: "Production",
        environment_key: "production",
        status: :queued,
        build_path: "/tmp/v1",
        preview_token: Ecto.UUID.generate(),
        preview_expires_at: DateTime.utc_now()
      })

      assert_stays(source, recipient, "ssg_builds", "creator_id")
    end

    test "a listing default stays, and two people's defaults do not collide", %{source: source, recipient: recipient} do
      for user <- [source, recipient] do
        view = Repo.insert!(%View{name: "Mine", schema: "S", listing: "default", creator_id: user.id})
        Repo.insert!(%Default{schema: "S", listing: "default", user_id: user.id, view_id: view.id})
      end

      assert {:ok, _} = Users.transfer_user_content(source.id, recipient.id)
      assert count("listing_view_defaults", "user_id", source.id) == 1
      assert count("listing_view_defaults", "user_id", recipient.id) == 1
    end

    test "a private listing view stays and a shared one moves", %{source: source, recipient: recipient} do
      Repo.insert!(%View{name: "Private", schema: "S", listing: "default", creator_id: source.id})
      Repo.insert!(%View{name: "Team", schema: "S", listing: "default", creator_id: source.id, shared: true})

      assert [%{table: "listing_views", count: 1}] =
               source.id |> Users.get_user_content_summary() |> Enum.filter(&(&1.table == "listing_views"))

      assert {:ok, _} = Users.transfer_user_content(source.id, recipient.id)

      names = fn id -> Repo.all(from v in View, where: v.creator_id == ^id, select: v.name) end
      assert names.(source.id) == ["Private"]
      assert names.(recipient.id) == ["Team"]
    end

    test "a shared listing view whose name the recipient has stays, and the transfer goes through", c do
      Repo.insert!(%View{name: "Team", schema: "S", listing: "default", creator_id: c.source.id, shared: true})
      Repo.insert!(%View{name: "Team", schema: "S", listing: "default", creator_id: c.recipient.id})

      assert {:ok, _} = Users.transfer_user_content(c.source.id, c.recipient.id)
      assert count("listing_views", "creator_id", c.source.id) == 1
    end

    # A row that dies with the account belongs to it: the foreign key says so.
    # A new table like that is not content, and has to be left out of the transfer.
    test "no reference that cascades from the account moves" do
      %{rows: rows} =
        Repo.query!("""
        SELECT DISTINCT tc.table_name
        FROM information_schema.table_constraints tc
        JOIN information_schema.constraint_column_usage ccu ON ccu.constraint_name = tc.constraint_name
        JOIN information_schema.referential_constraints rc ON rc.constraint_name = tc.constraint_name
        WHERE tc.constraint_type = 'FOREIGN KEY' AND ccu.table_name = 'users' AND rc.delete_rule = 'CASCADE'
        """)

      for [table] <- rows, table != "listing_views" do
        assert Users.transferred_table?(table) == false, "#{table} cascades from users but moves in a transfer"
      end
    end
  end

  describe "the current password" do
    @attrs %{"password" => "a new password", "password_confirmation" => "a new password"}

    setup do
      %{user: Repo.get!(User, TestUsers.insert_user(role: :admin, password: Bcrypt.hash_pwd_salt("admin")).id)}
    end

    defp failed_events(user) do
      Repo.aggregate(from(e in SecurityEvent, where: e.user_id == ^user.id and e.action == :login_failed), :count)
    end

    test "five wrong answers lock the account", %{user: user} do
      for _ <- 1..4, do: assert({:error, _} = Users.update_user_password(user, "wrong", @attrs))
      refute Throttle.locked_until(user)

      assert {:error, _} = Users.update_user_password(user, "wrong", @attrs)
      assert Throttle.locked_until(user)
      assert failed_events(user) == 5
    end

    test "a locked account is refused even the right password", %{user: user} do
      for _ <- 1..5, do: Users.update_user_password(user, "wrong", @attrs)

      assert {:error, changeset} = Users.update_user_password(user, "admin", @attrs)
      assert {_, _} = changeset.errors[:current_password]
      assert Bcrypt.verify_pass("admin", Repo.get!(User, user.id).password)
    end

    test "a mismatched pair cannot probe without counting", %{user: user} do
      mismatched = %{"password" => "a new password", "password_confirmation" => "another"}

      for _ <- 1..5, do: assert({:error, _} = Users.update_user_password(user, "wrong", mismatched))
      assert Throttle.locked_until(user)
    end

    test "the screen counts and shows a wrong answer", %{user: user} do
      {:ok, view, _} = live(log_in_user(build_conn(), user), "/admin/users/password")

      html = view |> form("#password_form", user: Map.put(@attrs, "current_password", "wrong")) |> render_submit()

      assert html =~ "is not your current password"
      assert failed_events(user) == 1
    end
  end

  describe "the password in logs" do
    test "a rejected user form logs no password", %{conn: conn} do
      marker = "marker-password-#{System.unique_integer([:positive])}"

      log =
        capture_log(fn ->
          {:ok, view, _} = live(conn, "/admin/users/create")
          render_async(view, 5_000)
          await_selector(view, "#user_form_form input")

          view
          |> form("#user_form_form", %{"user" => %{"name" => "", "email" => "a@example.net", "password" => marker}})
          |> render_submit()

          render(view)
        end)

      assert log =~ "Saving Brando.Users.User failed"
      refute log =~ marker
      refute log =~ "a@example.net"
    end

    test "a rejected update logs the errors, not what was typed" do
      admin = TestUsers.insert_user(role: :admin)
      editor = TestUsers.insert_user(role: :editor)
      changeset = editor |> Ecto.Changeset.change(name: "typed name") |> Ecto.Changeset.add_error(:name, "not this one")

      log = capture_log(fn -> assert {:error, _} = Users.update_user(changeset, admin) end)

      assert log =~ "not this one"
      refute log =~ "typed name"
    end

    test "inspecting a user or a changeset omits the password" do
      user = TestUsers.insert_user(role: :editor)

      refute inspect(user) =~ user.password
      refute inspect(Ecto.Changeset.change(user, password: "marker-password")) =~ "marker-password"
    end
  end
end
