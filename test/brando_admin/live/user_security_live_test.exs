defmodule BrandoAdmin.UserSecurityLiveTest do
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Factory
  alias Brando.Users
  alias Brando.Users.Security
  alias Brando.Users.SecurityEvent
  alias Brando.Users.SecurityPolicy
  alias Brando.Users.TwoFactor
  alias Brando.Users.UserConfig

  defp secret_from(html) do
    [text] = Regex.run(~r/data-testid="two-factor-secret"[^>]*>([^<]+)</, html, capture: :all_but_first)
    {:ok, secret} = Base.decode32(String.replace(text, " ", ""), padding: false)
    secret
  end

  # Keeping the test's session, which turning it on would otherwise end
  defp enable(user, conn) do
    secret = TwoFactor.new_secret()

    {:ok, codes} =
      TwoFactor.enable(user, secret, TwoFactor.current_code(secret), keep_token: get_session(conn, :user_token))

    BrandoIntegration.Repo.update_all(from(s in Security, where: s.user_id == ^user.id), set: [totp_last_step: nil])
    {secret, codes}
  end

  describe "the security page" do
    test "sets up two-factor authentication and shows the codes once", %{conn: conn, current_user: user} do
      other_session = Users.generate_user_session_token(user)
      {:ok, view, html} = live(conn, "/admin/users/security")
      assert html =~ ~s(data-enabled="false")

      html = view |> element("[data-testid=two-factor-setup]") |> render_click()
      secret = secret_from(html)

      html =
        view
        |> form("#two-factor-setup-form", setup: %{code: "000000"})
        |> render_submit()

      assert html =~ "did not match"
      refute TwoFactor.enabled?(user)

      view
      |> form("#two-factor-setup-form", setup: %{code: TwoFactor.current_code(secret)})
      |> render_submit()

      html = render(view)
      assert html =~ ~s(data-enabled="true")
      assert length(Regex.scan(~r/data-testid="recovery-code"/, html)) == 10

      # This session stays, the other one ends
      assert Users.get_user_by_session_token(get_session(conn, :user_token))
      refute Users.get_user_by_session_token(other_session)

      html = view |> element("[data-testid=recovery-codes-done]") |> render_click()
      refute html =~ ~s(data-testid="recovery-code")
      assert html =~ "Two-factor authentication turned on"
    end

    test "turning it off asks for the password or a code", %{conn: conn, current_user: user} do
      enable(user, conn)
      {:ok, view, _html} = live(conn, "/admin/users/security")

      view |> element("[data-testid=two-factor-disable]") |> render_click()
      html = view |> form("#security-confirm-form", confirm: %{proof: "wrong"}) |> render_submit()
      assert html =~ "not your password"
      assert TwoFactor.enabled?(user)

      view |> form("#security-confirm-form", confirm: %{proof: "admin"}) |> render_submit()
      assert render(view) =~ ~s(data-enabled="false")
      refute TwoFactor.enabled?(user)
    end

    test "new recovery codes ask for a code, and replace the old ones", %{conn: conn, current_user: user} do
      {secret, [old | _]} = enable(user, conn)
      {:ok, view, _html} = live(conn, "/admin/users/security")

      view |> element("[data-testid=recovery-codes-regenerate]") |> render_click()
      view |> form("#security-confirm-form", confirm: %{proof: TwoFactor.current_code(secret)}) |> render_submit()

      html = render(view)
      assert length(Regex.scan(~r/data-testid="recovery-code"/, html)) == 10
      assert {:error, :invalid} = TwoFactor.verify(user, old)
    end
  end

  describe "the user form" do
    test "a superuser resets another user's two-factor authentication", %{conn: conn, current_user: admin} do
      user = Factory.insert(:random_user, role: :editor, avatar: nil, config: %UserConfig{})
      enable(user, conn)

      {:ok, view, _html} = live(conn, "/admin/users/update/#{user.id}")
      assert await_selector(view, "[data-testid=reset-two-factor]")

      view |> element("[data-testid=reset-two-factor]") |> render_click()
      refute TwoFactor.enabled?(user)

      assert [%{actor_id: actor_id}] =
               BrandoIntegration.Repo.all(
                 from e in SecurityEvent, where: e.user_id == ^user.id and e.action == :two_factor_reset
               )

      assert actor_id == admin.id
    end

    test "your own form links to your security page", %{conn: conn, current_user: user} do
      BrandoIntegration.Repo.update_all(from(u in Brando.Users.User, where: u.id == ^user.id), set: [avatar_id: nil])
      {:ok, view, _html} = live(conn, "/admin/users/update/#{user.id}")
      assert await_selector(view, "[data-testid=open-security]")
      refute has_element?(view, "[data-testid=reset-two-factor]")
    end
  end

  describe "the sign-in policy" do
    test "a superuser saves it once they use two-factor authentication", %{conn: conn, current_user: admin} do
      {:ok, view, _html} = live(conn, "/admin/users/sign-in-policy")

      html = view |> form("#sign-in-policy-form", policy: %{two_factor: "everyone"}) |> render_submit()
      assert html =~ "Set up two-factor authentication on your Security page first"
      assert SecurityPolicy.get().two_factor == :off

      view |> form("#sign-in-policy-form", policy: %{two_factor: "selected"}) |> render_change()

      view
      |> form("#sign-in-policy-form", policy: %{two_factor: "selected", two_factor_roles: ["", "editor"]})
      |> render_submit()

      assert %{two_factor: :selected, two_factor_roles: ["editor"]} = SecurityPolicy.get()
      enable(admin, conn)

      view |> form("#sign-in-policy-form", policy: %{two_factor: "everyone"}) |> render_submit()
      assert SecurityPolicy.get().two_factor == :everyone
    end

    test "is for superusers only" do
      editor = Factory.insert(:random_user, role: :editor, config: %UserConfig{reset_password_on_first_login: false})
      conn = log_in_user(Phoenix.ConnTest.build_conn(), editor)

      assert {:error, {:live_redirect, %{to: "/admin/users"}}} = live(conn, "/admin/users/sign-in-policy")
    end
  end
end
