defmodule Brando.Authorization.RealtimeTest do
  use Brando.ConnCase
  import Phoenix.ChannelTest
  alias Brando.Authorization.{Boundary, Groups, Migration, Preview, Realtime, Scope}
  alias Brando.Factory
  alias Brando.Pages.Page

  setup do
    put_test_env(:authorization_mode, :groups)
    put_test_env(:tenancy_mode, :none)
    Boundary.put_scope(nil)
    Brando.Tenant.put_prefix(nil)
    owner = Factory.insert(:random_user, role: :superuser, avatar: nil)
    editor = Factory.insert(:random_user, role: :editor, avatar: nil)
    outsider = Factory.insert(:random_user, role: :user, avatar: nil)
    page = Factory.insert(:page, status: :draft)
    {:ok, _} = Migration.run()
    scope = Scope.standalone(editor)
    key = "AUTH-PREVIEW-#{Ecto.UUID.generate()}"
    changeset = Ecto.Changeset.change(page)
    assert :ok = Boundary.with_scope(scope, fn -> Preview.register(key, changeset) end)
    Brando.LivePreview.store_cache(key, "<html><body><main>Private draft</main></body></html>")

    on_exit(fn ->
      Boundary.put_scope(nil)
      Preview.cleanup(key)
      Cachex.del(:cache, "__live_preview__#{key}")
    end)

    %{owner: owner, editor: editor, outsider: outsider, page: page, scope: scope, key: key, changeset: changeset}
  end

  test "only the creator can read an unsaved preview, with no browser caching", c do
    conn = preview_conn(c.editor, c.key)
    assert conn.status == 200
    assert conn.resp_body =~ "Private draft"
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]

    for user <- [c.owner, c.outsider] do
      conn = preview_conn(user, c.key)
      assert conn.status == 403
      refute conn.resp_body =~ "Private draft"
    end

    assert preview_conn(c.editor, "unknown").status == 403

    assert build_conn(:get, "/__livepreview")
           |> init_test_session(%{})
           |> Brando.Plug.LivePreview.call([])
           |> Map.get(:status) == 403
  end

  test "preview reads reload both authority and the target record", c do
    {:ok, groups} = Groups.list(Scope.standalone(c.owner))
    group = Enum.find(groups, &(&1.preset == :editor))
    {:ok, :ok} = Groups.remove_member(Scope.standalone(c.owner), group.id, c.editor.id)
    assert preview_conn(c.editor, c.key).status == 403
    assert {:error, :forbidden} = Preview.authorize(c.key, c.editor.id)
  end

  test "deleting a previewed entry closes access to its cached draft", c do
    Repo.update!(Ecto.Changeset.change(c.page, deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)))
    assert {:error, :forbidden} = Preview.authorize(c.key, c.editor.id)
  end

  test "another form, actor, or absent scope cannot overwrite a preview", c do
    other = Factory.insert(:page, status: :draft)
    assert {:error, :forbidden} = Preview.authorize_write(c.key, c.changeset)
    assert {:error, :forbidden} = Brando.LivePreview.switch_target(Page, c.changeset, c.key, :listing)

    Boundary.with_scope(Scope.standalone(c.owner), fn ->
      assert {:error, :forbidden} = Preview.authorize_write(c.key, c.changeset)
    end)

    Boundary.with_scope(c.scope, fn ->
      assert :ok = Preview.authorize_write(c.key, c.changeset)
      assert {:error, :forbidden} = Preview.authorize_write(c.key, Ecto.Changeset.change(other))
      assert {:error, :forbidden} = Brando.LivePreview.update(Page, Ecto.Changeset.change(other), c.key)
      assert {:error, :forbidden} = Brando.LivePreview.switch_target(Page, Ecto.Changeset.change(other), c.key, :listing)
    end)

    assert {:ok, html} = Brando.LivePreview.get_cache(c.key)
    assert html =~ "Private draft"
  end

  test "disabled and deleted accounts cannot connect with existing signed socket tokens", c do
    for attrs <- [%{active: false}, %{deleted_at: ~U[2026-01-01 00:00:00Z]}] do
      Repo.update_all(from(user in Brando.Users.User, where: user.id == ^c.editor.id), set: [active: true])
      token = socket_token(c.editor)
      assert {:ok, _socket} = BrandoAdmin.AdminSocket.connect(%{"token" => token}, %Phoenix.Socket{})
      Repo.update!(Ecto.Changeset.change(c.editor, attrs))
      assert :error = BrandoAdmin.AdminSocket.connect(%{"token" => token}, %Phoenix.Socket{})
    end

    assert :error = BrandoAdmin.AdminSocket.connect(%{"token" => socket_token(c.outsider)}, %Phoenix.Socket{})
  end

  # As BrandoAdmin.AdminSocket.connect/2 assigns it, for a live session
  defp admin_socket(user, id) do
    session_id = Brando.Users.token_id(Brando.Users.generate_user_session_token(user))
    socket(BrandoAdmin.AdminSocket, id, %{user_id: user.id, session_id: session_id})
  end

  defp socket_token(user) do
    session = Brando.Users.generate_user_session_token(user)
    Brando.Users.build_socket_token(user, Brando.Users.token_id(session))
  end

  test "a late preview subscriber receives changes made since the iframe loaded", c do
    assert preview_conn(c.editor, c.key).resp_body =~ "Private draft"

    html = "<html><body><main>Recovered unsaved blocks</main></body></html>"
    Brando.LivePreview.store_cache(c.key, html)
    Brando.endpoint().broadcast("live_preview:#{c.key}", "rerender", %{html: html})

    socket = admin_socket(c.editor, "preview")
    assert {:ok, _, _} = subscribe_and_join(socket, Brando.LivePreviewChannel, "live_preview:#{c.key}")
    assert_push "rerender", %{html: ^html}
  end

  test "preview channels stop on revocation and recheck each outgoing update", c do
    socket = admin_socket(c.editor, "preview")
    {:ok, _, joined} = subscribe_and_join(socket, Brando.LivePreviewChannel, "live_preview:#{c.key}")
    monitor = Process.monitor(joined.channel_pid)
    broadcast_from!(joined, "update", %{html: "Allowed draft"})
    assert_push "update", %{html: "Allowed draft"}
    Repo.update!(Ecto.Changeset.change(c.editor, active: false))
    broadcast_from!(joined, "update", %{html: "Forbidden draft"})
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    refute_push "update", %{html: "Forbidden draft"}

    assert {:error, %{reason: "forbidden"}} =
             subscribe_and_join(socket, Brando.LivePreviewChannel, "live_preview:#{c.key}")
  end

  test "a permission-change broadcast closes an already joined preview", c do
    socket = admin_socket(c.editor, "preview")
    {:ok, _, joined} = subscribe_and_join(socket, Brando.LivePreviewChannel, "live_preview:#{c.key}")
    monitor = Process.monitor(joined.channel_pid)
    {:ok, groups} = Groups.list(Scope.standalone(c.owner))
    group = Enum.find(groups, &(&1.preset == :editor))
    {:ok, :ok} = Groups.remove_member(Scope.standalone(c.owner), group.id, c.editor.id)
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
  end

  test "scope tokens are bound to the account and are rechecked after revocation", c do
    token = Realtime.token(c.scope)
    assert {:ok, scope} = Realtime.verify_scope(token, c.editor.id)
    assert scope == c.scope
    assert {:error, :forbidden} = Realtime.verify_scope(token, c.owner.id)
    assert {:error, :forbidden} = Realtime.verify_scope("forged", c.editor.id)
    Repo.update!(Ecto.Changeset.change(c.editor, active: false))
    assert {:error, :forbidden} = Realtime.verify_scope(token, c.editor.id)
  end

  test "lobby joins require signed scope and never forward raw presence diffs", c do
    Phoenix.PubSub.subscribe(Brando.pubsub(), "presence")
    socket = admin_socket(c.editor, "lobby")
    assert {:error, %{reason: "forbidden"}} = subscribe_and_join(socket, Brando.LobbyChannel, "lobby", %{url: "/admin"})

    {:ok, _, joined} =
      subscribe_and_join(socket, Brando.LobbyChannel, "lobby", %{url: "/admin", scope_token: Realtime.token(c.scope)})

    assert_receive {BrandoAdmin.Presence, {:presence, %{user_joined: _}}}
    broadcast_from!(joined, "presence_diff", %{joins: %{secret: "Other site activity"}})
    refute_push "presence_diff", _
    monitor = Process.monitor(joined.channel_pid)
    Repo.update!(Ecto.Changeset.change(c.editor, active: false))
    Phoenix.PubSub.broadcast(Brando.pubsub(), "brando:authorization", {:authorization_changed, :all})
    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    assert_receive {BrandoAdmin.Presence, {:presence, %{user_left: _}}}
  end

  test "shareable previews require export as well as current edit access", c do
    assert :ok = Boundary.with_scope(c.scope, fn -> Preview.authorize_share(c.editor, c.changeset) end)
    assert {:error, :forbidden} = Preview.authorize_share(c.outsider, c.changeset)
    {:ok, groups} = Groups.list(Scope.standalone(c.owner))
    group = Enum.find(groups, &(&1.preset == :editor))
    keys = Enum.map(group.grants, & &1.permission_key) -- ["brando.pages.export"]
    {:ok, _} = Groups.update(Scope.standalone(c.owner), group.id, %{}, keys, group.lock_version)
    assert :ok = Preview.authorize(c.key, c.editor.id)
    assert {:error, :forbidden} = Boundary.with_scope(c.scope, fn -> Preview.authorize_share(c.editor, c.changeset) end)
  end

  test "lobby mutation notifications strip authority metadata and drop unreadable records", c do
    Phoenix.PubSub.subscribe(Brando.pubsub(), "presence")
    socket = admin_socket(c.editor, "lobby")

    {:ok, _, joined} =
      subscribe_and_join(socket, Brando.LobbyChannel, "lobby", %{url: "/admin", scope_token: Realtime.token(c.scope)})

    assert_receive {BrandoAdmin.Presence, {:presence, %{user_joined: _}}}

    payload = %{
      type: :mutation,
      payload: "Allowed",
      authorization: %{prefix: c.scope.prefix, schema: Page, entry_id: c.page.id}
    }

    broadcast_from!(joined, "toast", payload)
    assert_push "toast", %{type: :mutation, payload: "Allowed"} = delivered
    refute Map.has_key?(delivered, :authorization)
    broadcast_from!(joined, "toast", put_in(payload, [:authorization, :prefix], "another_site"))
    refute_push "toast", _
    Process.unlink(joined.channel_pid)
    close(joined)
    assert_receive {BrandoAdmin.Presence, {:presence, %{user_left: _}}}
  end

  defp preview_conn(user, key) do
    token = Brando.Users.generate_user_session_token(user)

    build_conn(:get, "/__livepreview?key=#{key}")
    |> init_test_session(%{user_token: token})
    |> Brando.Plug.LivePreview.call([])
  end
end
