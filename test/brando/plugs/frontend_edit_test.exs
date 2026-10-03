defmodule Brando.Plug.FrontendEditTest do
  use ExUnit.Case, async: false
  use Brando.ConnCase

  import Brando.FrontendEditFixtures

  alias Brando.Factory
  alias Brando.FrontendEdit
  alias Brando.Plug.FrontendEdit, as: FrontendEditPlug

  setup do
    previous = Application.get_env(:brando, FrontendEdit)
    Application.put_env(:brando, FrontendEdit, enabled: true)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:brando, FrontendEdit, previous),
        else: Application.delete_env(:brando, FrontendEdit)

      FrontendEdit.deactivate()
    end)

    user = Factory.insert(:random_user, role: :superuser, language: :en)
    {:ok, user: user}
  end

  defp signed_in(conn, user) do
    token = Brando.Users.generate_user_session_token(user)
    conn |> Plug.Test.init_test_session(%{}) |> Plug.Conn.put_session(:user_token, token)
  end

  defp edit_mode(conn), do: Plug.Test.put_req_cookie(conn, FrontendEdit.cookie(), "1")

  # Runs the plug and then a "controller" that renders `body` the way a page
  # would in this request.
  defp request(conn, body_fun) do
    conn = FrontendEditPlug.call(conn, FrontendEditPlug.init([]))

    conn
    |> Plug.Conn.put_resp_content_type("text/html")
    |> Plug.Conn.send_resp(200, body_fun.())
  end

  defp page_body(page),
    do: "<html><body><main>#{Phoenix.HTML.safe_to_string(Phoenix.HTML.html_escape(page))}</main></body></html>"

  defp config(conn) do
    [_, json] =
      Regex.run(~r/<script type="application\/json" id="brando-frontend-edit-config">(.*?)<\/script>/s, conn.resp_body)

    Jason.decode!(json)
  end

  test "visitors get the page untouched", %{user: user} do
    %{page: page} = page_with_blocks(user)

    conn =
      request(build_conn(:get, "/about") |> Plug.Test.init_test_session(%{}) |> edit_mode(), fn -> page_body(page) end)

    refute conn.resp_body =~ "brando-frontend-edit"
    refute conn.resp_body =~ "[+:B<"
    assert Plug.Conn.get_resp_header(conn, "cache-control") != ["private, no-store"]
  end

  test "nothing is added when frontend edit is switched off", %{user: user} do
    Application.put_env(:brando, FrontendEdit, enabled: false)
    %{page: page} = page_with_blocks(user)

    conn = request(build_conn(:get, "/about") |> signed_in(user) |> edit_mode(), fn -> page_body(page) end)

    refute conn.resp_body =~ "brando-frontend-edit"
    refute FrontendEdit.active?()
  end

  test "an admin gets the button, without markers or a manifest", %{user: user} do
    %{page: page} = page_with_blocks(user)

    conn = request(build_conn(:get, "/about") |> signed_in(user), fn -> page_body(page) end)

    assert %{"active" => false, "manifest" => nil, "editorUrl" => "/admin/frontend-edit", "text" => text} = config(conn)
    assert text["editPage"] == "Edit page"
    refute conn.resp_body =~ "[+:B<"
    refute conn.resp_body =~ "window.BrandoBlockPatch ="
    assert Plug.Conn.get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  test "in edit mode the page is marked and comes with its manifest", %{user: user} do
    %{page: page, intro: intro} = page_with_blocks(user)

    conn = request(build_conn(:get, "/about") |> signed_in(user) |> edit_mode(), fn -> page_body(page) end)

    assert conn.resp_body =~ "<!-- [+:B<#{intro.uid}>] -->"
    assert conn.resp_body =~ "window.BrandoBlockPatch ="
    assert %{"active" => true, "manifest" => %{"blocks" => blocks, "owners" => owners}} = config(conn)
    assert blocks[intro.uid]["target"] == intro.uid
    assert [%{"editable" => true, "label" => "About us"}] = Map.values(owners)
    # The request's edit mode ends with the response
    refute FrontendEdit.active?()
  end

  test "the overlay copy is in the admin's language", %{user: user} do
    user = user |> Ecto.Changeset.change(language: :no) |> Brando.Repo.update!()
    %{page: page} = page_with_blocks(user)

    conn = request(build_conn(:get, "/about") |> signed_in(user), fn -> page_body(page) end)

    assert config(conn)["text"]["editPage"] == "Rediger side"
    # The page itself stays in its own language
    refute Gettext.get_locale(Brando.Gettext) == "no"
  end

  test "the manifest escapes HTML in entry titles", %{user: user} do
    %{page: page} = page_with_blocks(user, title: "</script><script>alert(1)</script>")

    conn = request(build_conn(:get, "/about") |> signed_in(user) |> edit_mode(), fn -> page_body(page) end)

    refute conn.resp_body =~ "<script>alert(1)"
    assert [%{"label" => "</script><script>alert(1)</script>"}] = Map.values(config(conn)["manifest"]["owners"])
  end

  test "responses that are not HTML pages pass through", %{user: user} do
    conn =
      build_conn(:get, "/feed.json")
      |> signed_in(user)
      |> FrontendEditPlug.call([])
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(200, ~s({"ok":true}))

    assert conn.resp_body == ~s({"ok":true})

    conn =
      build_conn(:post, "/form")
      |> signed_in(user)
      |> FrontendEditPlug.call([])

    refute Map.has_key?(conn.private, :brando_frontend_edit)
  end

  test "a stale edit mode from an earlier request on the connection is cleared" do
    FrontendEdit.activate()
    FrontendEditPlug.call(build_conn(:get, "/") |> Plug.Test.init_test_session(%{}), [])
    refute FrontendEdit.active?()
  end

  test "shared previews and Brando's own routes pass through", %{user: user} do
    for path <- ["/__p__/KEY", "/__ssg_preview__/token/about", "/__brando/forms/csrf-token"] do
      conn = build_conn(:get, path) |> signed_in(user) |> FrontendEditPlug.call([])
      refute Map.has_key?(conn.private, :brando_frontend_edit)
    end
  end

  test "a pipeline without a session passes through" do
    conn = FrontendEditPlug.call(build_conn(:get, "/"), [])
    refute Map.has_key?(conn.private, :brando_frontend_edit)
  end
end
