defmodule BrandoAdmin.LobbyChannelSiteAccessTest do
  # Audit F24: in legacy authorization with several sites, a lobby channel
  # signed inside a site kept delivering that site's mutation toasts after the
  # user lost access to it.
  use Brando.ConnCase
  import Phoenix.ChannelTest

  alias Brando.Authorization.{Realtime, Scope}
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.Tenant.{Access, Cache, Registry}
  alias Brando.Users.UserSite

  setup do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :multi)
    Brando.Tenant.put_prefix(nil)
    Cache.clear()
    on_exit(&Cache.clear/0)

    {alpha, alpha_env} = site("lobby-alpha")
    {beta, beta_env} = site("lobby-beta")
    editor = Factory.insert(:random_user, role: :editor, avatar: nil)
    {:ok, _} = Access.grant(editor, alpha, :editor)
    {:ok, _} = Access.grant(editor, beta, :editor)

    %{
      editor: editor,
      alpha: alpha,
      alpha_scope: Scope.site(editor, alpha, alpha_env),
      beta_scope: Scope.site(editor, beta, beta_env)
    }
  end

  test "revoking site access closes the open channel and refuses a replayed join", c do
    token = Realtime.token(c.alpha_scope)
    joined = join!(c.editor, token)
    monitor = Process.monitor(joined.channel_pid)

    :ok = Access.revoke(c.editor, c.alpha)

    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    assert {:error, :forbidden} = Realtime.verify_scope(token, c.editor.id)
    assert {:error, %{reason: "forbidden"}} = join_lobby(c.editor, token)

    # Still assigned to the other site
    assert {:ok, _scope} = Realtime.verify_scope(Realtime.token(c.beta_scope), c.editor.id)
  end

  test "each toast checks site access again", c do
    joined = join!(c.editor, Realtime.token(c.alpha_scope))

    broadcast_from!(joined, "toast", toast(c.alpha_scope.prefix, "Before"))
    assert_push "toast", %{payload: "Before"}

    # Removed without a broadcast, as another node or a direct write might
    Repo.delete_all(from(user_site in UserSite, where: user_site.site_id == ^c.alpha.id), prefix: "public")

    broadcast_from!(joined, "toast", toast(c.alpha_scope.prefix, "AlphaSecret"))
    refute_push "toast", %{payload: "AlphaSecret"}
  end

  test "suspending the site closes its channels", c do
    joined = join!(c.editor, Realtime.token(c.alpha_scope))
    monitor = Process.monitor(joined.channel_pid)

    {:ok, _site} = Registry.update_site(c.alpha, %{status: :suspended})

    assert_receive {:DOWN, ^monitor, :process, _, :normal}
    assert {:error, %{reason: "forbidden"}} = join_lobby(c.editor, Realtime.token(c.alpha_scope))
  end

  # A single site lets every account in, assigned or not (Brando.Tenant.AdminContext)
  test "with one site, an editor with no assignment still joins", c do
    put_test_env(:tenancy_mode, :single)
    put_test_env(:site_key, c.alpha.key)
    editor = Factory.insert(:random_user, role: :editor, avatar: nil)
    scope = Scope.site(editor, c.alpha, hd(c.alpha.environments))

    assert {:ok, _scope} = Realtime.verify_scope(Realtime.token(scope), editor.id)
  end

  defp join!(user, token) do
    Phoenix.PubSub.subscribe(Brando.pubsub(), "presence")
    {:ok, _, joined} = join_lobby(user, token)
    assert_receive {BrandoAdmin.Presence, {:presence, %{user_joined: _}}}
    Process.unlink(joined.channel_pid)
    joined
  end

  defp join_lobby(user, token) do
    session_id = Brando.Users.token_id(Brando.Users.generate_user_session_token(user))
    socket = socket(BrandoAdmin.AdminSocket, "lobby-#{System.unique_integer()}", %{user_id: user.id, session_id: session_id})
    subscribe_and_join(socket, BrandoAdmin.LobbyChannel, "lobby", %{url: "/admin", scope_token: token})
  end

  defp toast(prefix, message),
    do: %{type: :mutation, payload: message, authorization: %{prefix: prefix, schema: Page, entry_id: 1}}

  defp site(key) do
    key = "#{key}-#{System.unique_integer([:positive])}"

    {:ok, site} =
      Registry.create_site(%{name: key, key: key, languages: ["en"], default_language: "en", status: :active})

    {:ok, environment} = Registry.create_environment(site, %{name: "Production", key: "production", live: true})
    {Registry.get_site(site.id), environment}
  end
end
