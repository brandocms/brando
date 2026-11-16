defmodule BrandoAdmin.ContentLanguageSwitchTest do
  # The content language row at the foot of the sidebar: it names the language
  # being edited and opens a list to switch.
  use Brando.LiveCase, async: true

  test "names the content language and lists the others on click", %{conn: conn} do
    {:ok, view, html} = live(conn, "/admin/pages")

    assert html =~ "content-language-selector"
    assert html =~ ~r/Content in <strong>[^<]+<\/strong>/
    refute has_element?(view, ".content-language-selector .languages")

    view |> element(".content-language-selector .current-language") |> render_click()
    assert has_element?(view, ".content-language-selector .languages button.current")
    assert view |> element(".content-language-selector .languages") |> render() =~ ~s(role="option")

    view |> element(".content-language-selector .current-language") |> render_click()
    refute has_element?(view, ".content-language-selector .languages")
  end
end

defmodule BrandoAdmin.ContentLanguageSwitchViewsTest do
  # Choosing a content language works on every admin screen: a listing, a
  # screen with a handle_info of its own (the calendar) and one without.
  use Brando.LiveCase, async: true

  setup do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
  end

  defp stored(user), do: Brando.Repo.get!(Brando.Users.User, user.id).config.content_language

  defp switch(view, user) do
    language = if stored(user) == "no", do: "en", else: "no"
    view |> element(".content-language-selector .current-language") |> render_click()
    view |> element(".content-language-selector .languages button[phx-value-id='#{language}']") |> render_click()
    language
  end

  defp assert_switched(view, user, language) do
    # The switch's message is handled before this render
    html = render(view)
    assert stored(user) == language
    assert :sys.get_state(view.pid).socket.assigns.current_user.config.content_language == language

    name = if language == "no", do: "Norsk", else: "English"
    assert html =~ "Content in <strong>#{name}</strong>"
  end

  for path <- ["/admin/calendar", "/admin/config/cache"] do
    test "saves the language and keeps #{path} running", %{conn: conn, current_user: user} do
      {:ok, view, _html} = live(conn, unquote(path))
      language = switch(view, user)
      assert_switched(view, user, language)
    end
  end

  test "a form follows the new language", %{conn: conn, current_user: user} do
    {:ok, _user} = Brando.Users.update_user(user, %{config: %{content_language: "en"}}, :system, show_notification: false)
    english = Brando.Repo.get_by!(Brando.Sites.Identity, language: :en)
    {:ok, norwegian} = Brando.Sites.duplicate_identity(english.id, :system, merge_fields: %{language: :no})
    {view, _html} = live_form(conn, "/admin/config/identity", "identity_form")
    assert :sys.get_state(view.pid).socket.assigns.entry_id == english.id

    "no" = switch(view, user)
    assert_switched(view, user, "no")

    # The identity screen opens the Norwegian identity (its handle_info for the
    # form hook's {:content_language, _})
    assert :sys.get_state(view.pid).socket.assigns.entry_id == norwegian.id
  end

  for {path, form_id, schema} <- [
        {"/admin/config/identity", "identity_form", Brando.Sites.Identity},
        {"/admin/config/seo", "seo_form", Brando.Sites.SEO}
      ] do
    test "#{path} makes the entry for a language that has none yet", %{conn: conn, current_user: user} do
      {:ok, _user} =
        Brando.Users.update_user(user, %{config: %{content_language: "en"}}, :system, show_notification: false)

      refute Brando.Repo.get_by(unquote(schema), language: :no)
      {view, _html} = live_form(conn, unquote(path), unquote(form_id))

      "no" = switch(view, user)
      assert_switched(view, user, "no")

      norwegian = Brando.Repo.get_by!(unquote(schema), language: :no)
      assert :sys.get_state(view.pid).socket.assigns.entry_id == norwegian.id
    end
  end

  test "a listing shows its entries in the new language", %{conn: conn, current_user: user} do
    {:ok, user} = Brando.Users.update_user(user, %{config: %{content_language: "en"}}, :system, show_notification: false)
    Factory.insert(:page, title: "An English page", language: :en, creator: user)
    Factory.insert(:page, title: "En norsk side", language: :no, creator: user)

    {:ok, view, html} = live(conn, "/admin/pages")
    assert html =~ "An English page"
    refute html =~ "En norsk side"

    "no" = switch(view, user)
    assert_switched(view, user, "no")
    assert render(view) =~ "En norsk side"
    refute render(view) =~ "An English page"
  end
end
