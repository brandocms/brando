defmodule BrandoAdmin.ListingDuplicateToLanguageTest do
  # The Pages listing's "Duplicate to [NO]" copies a page into another
  # language. The Index page is the common case where that language already
  # has a page at the same URI: the copy used to hit the unique index on
  # (uri, language), raise, and take the listing down.
  #
  # The LiveView runs in its own process, so the sandbox must be shared:
  # these tests can't be async.
  use Brando.ConnCase

  @moduletag :capture_log

  import Phoenix.LiveViewTest

  alias Brando.Factory
  alias Brando.Pages.Page

  @path "/admin/pages"

  setup %{conn: conn} do
    user = Factory.insert(:random_user, role: :superuser, config: %Brando.Users.UserConfig{})
    token = Brando.Users.generate_user_session_token(user)

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:user_token, token)
      |> Plug.Conn.put_session(:live_socket_id, "users_sessions:#{Base.url_encode64(token)}")

    no_index = Factory.insert(:page, title: "Indeks", uri: "index", language: :no)
    en_index = Factory.insert(:page, title: "Index", uri: "index", language: :en)
    en_about = Factory.insert(:page, title: "About", uri: "about", language: :en)

    # The rows render the creators' avatars, which the factory leaves without a focal point
    Repo.update_all(Brando.Images.Image, set: [focal: %Brando.Images.Focal{x: 50, y: 50}])

    %{conn: conn, current_user: user, no_index: no_index, en_index: en_index, en_about: en_about}
  end

  defp action(entry), do: "#action_default_duplicate_entry_to_lang_#{entry.id}_lang_no"

  defp norwegian_pages, do: Repo.all(from p in Page, where: p.language == :no, order_by: p.id)

  test "Duplicate to a language that uses the page's URI copies it to a free URI", c do
    {:ok, view, _html} = live(c.conn, @path)

    view |> element(action(c.en_index)) |> render_click()

    assert [_, copy] = norwegian_pages()
    assert copy.uri == "index-2"
    assert_redirect(view, "/admin/pages/update/#{copy.id}", 1_000)

    {:ok, en_index} = Brando.Pages.get_page(%{matches: %{id: c.en_index.id}, preload: [:alternate_entries]})
    assert Enum.map(en_index.alternate_entries, & &1.id) == [copy.id]
  end

  test "the bulk duplicate to a language that uses the page's URI copies it to a free URI", c do
    {:ok, view, _html} = live(c.conn, @path)

    render_click(view, "duplicate_selected_to_language", %{
      "ids" => Jason.encode!([c.en_index.id, c.en_about.id]),
      "language" => "no"
    })

    assert Process.alive?(view.pid)
    assert [_, _, _] = pages = norwegian_pages()
    assert pages |> Enum.map(& &1.uri) |> Enum.sort() == ["about", "index", "index-2"]
  end

  test "a language the page already has is not offered, and is refused if asked for", c do
    Page.Alternate.add(c.en_index.id, c.no_index.id)
    Brando.endpoint().subscribe("user:#{c.current_user.id}")

    {:ok, view, _html} = live(c.conn, @path)

    assert has_element?(view, "#action_default_duplicate_entry_#{c.en_index.id}")
    refute has_element?(view, action(c.en_index))

    render_click(view, "duplicate_entry_to_language", %{"id" => "#{c.en_index.id}", "language" => "no"})
    assert_receive %Phoenix.Socket.Broadcast{event: "toast"}

    assert Process.alive?(view.pid)
    assert Enum.map(norwegian_pages(), & &1.id) == [c.no_index.id]
  end
end
