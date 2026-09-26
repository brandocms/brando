defmodule BrandoAdmin.AssistantGuidanceLiveTest do
  use Brando.LiveCase

  alias Brando.AI.Agent.Guidance
  alias Brando.AI.Agent.Guidance.Version
  alias Brando.AIStub

  setup do
    AIStub.configure(shared: true)
    :ok
  end

  test "a superuser writes, saves and restores the guidance", %{conn: conn, current_user: user} do
    {:ok, view, html} = live(conn, "/admin/config/assistant")
    assert html =~ "Assistant guidance"
    assert html =~ "No guidance has been saved here yet."
    assert has_element?(view, "#guidance-form button[type=submit][disabled]")

    view |> form("#guidance-form", %{text: "Start articles with the Article lede module."}) |> render_change()
    refute has_element?(view, "#guidance-form button[type=submit][disabled]")
    view |> form("#guidance-form", %{text: "Start articles with the Article lede module."}) |> render_submit()

    assert Guidance.current().text == "Start articles with the Article lede module."
    assert has_element?(view, ".guidance-history li", "In use")
    assert render(view) =~ "Saved"

    view |> form("#guidance-form", %{text: "Something else"}) |> render_submit()
    [_current, first] = view |> render() |> Floki.parse_document!() |> Floki.find(".guidance-history li")
    assert Floki.text(first) =~ "Start articles"

    # Loading a version fills the editor; it is saved like any edit.
    view |> element(".guidance-history button", "Load into editor") |> render_click()
    assert has_element?(view, "#guidance-text", "Start articles with the Article lede module.")
    assert has_element?(view, ".guidance-note", "Restored the version from")
    view |> form("#guidance-form") |> render_submit()

    assert %{text: "Start articles with the Article lede module.", note: "Restored the version from " <> _} =
             Guidance.current()

    assert Guidance.current().author_id == user.id
  end

  test "guidance from another site or environment is copied into the editor", %{conn: conn} do
    Brando.Repo.insert!(%Version{
      scope: "other",
      prefix: "tenant_acme_staging",
      site_key: "acme",
      environment_key: "staging",
      text: "Acme's conventions."
    })

    {:ok, view, _html} = live(conn, "/admin/config/assistant")
    assert has_element?(view, "#guidance-source option", "acme / staging")

    view |> form("#guidance-copy") |> render_submit()
    assert has_element?(view, "#guidance-text", "Acme's conventions.")
    assert has_element?(view, ".guidance-note", "Copied from acme / staging")
    # Nothing is saved until the copy is saved.
    assert Guidance.current() == nil

    view |> form("#guidance-form") |> render_submit()
    assert %{text: "Acme's conventions.", note: "Copied from acme / staging"} = Guidance.current()
  end

  test "the developers' guidance is shown read-only", %{conn: conn} do
    previous = Application.get_env(:brando, Brando.AI.Agent)
    Application.put_env(:brando, Brando.AI.Agent, guidance: "From the code: keep headings short.")
    on_exit(fn -> Application.put_env(:brando, Brando.AI.Agent, previous || []) end)

    {:ok, view, _html} = live(conn, "/admin/config/assistant")
    assert has_element?(view, ".guidance-code pre", "From the code: keep headings short.")
  end

  test "users who may not configure the assistant are sent away, and do not see it in the menu", %{conn: conn} do
    admin = Factory.insert(:random_user, role: :admin, config: %Brando.Users.UserConfig{})
    conn = log_in_user(build_conn(), admin)
    assert {:error, {:redirect, %{to: "/admin"}}} = live(conn, "/admin/config/assistant")

    urls = fn user ->
      for %{items: items} <- BrandoAdmin.Menu.get_menu(user),
          item <- items,
          sub <- [item | item[:items] || []],
          do: sub[:url]
    end

    refute "/admin/config/assistant" in urls.(admin)
    assert "/admin/config/assistant" in urls.(Factory.insert(:random_user, role: :superuser))
  end

  test "editors can read the guidance the assistant follows", %{conn: conn, current_user: user} do
    {:ok, _} = Guidance.save("Portrait pairs use Two images with narrow on.", user)
    {:ok, view, _html} = live(conn, "/admin/assistant")
    assert has_element?(view, "#assistant-guidance summary", "Site guidance in use")
    assert has_element?(view, "#assistant-guidance pre", "Portrait pairs use Two images with narrow on.")
    assert has_element?(view, "#assistant-guidance a[href='/admin/config/assistant']", "Edit guidance")

    editor = Factory.insert(:random_user, role: :admin, config: %Brando.Users.UserConfig{})
    {:ok, view, _html} = live(log_in_user(build_conn(), editor), "/admin/assistant")
    assert has_element?(view, "#assistant-guidance pre", "Portrait pairs")
    refute has_element?(view, "#assistant-guidance a", "Edit guidance")
  end
end
