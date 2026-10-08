defmodule BrandoAdmin.FrontendEditLiveTest do
  use Brando.LiveCase

  import Brando.FrontendEditFixtures

  alias Brando.FrontendEdit
  alias Brando.Pages.Page

  @form "page_form"

  setup %{current_user: user} do
    previous = Application.get_env(:brando, FrontendEdit)
    Application.put_env(:brando, FrontendEdit, enabled: true)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:brando, FrontendEdit, previous),
        else: Application.delete_env(:brando, FrontendEdit)
    end)

    page_with_blocks(user)
  end

  defp editor(conn, uid, form \\ @form), do: live_form(conn, "/admin/frontend-edit?uid=#{uid}", form)

  defp save(view) do
    view |> form("##{@form}_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form("##{@form}_form") |> render_submit()
  end

  test "opens the block alone, under the entry it belongs to", %{conn: conn, intro: intro, container: container} do
    {view, html} = editor(conn, intro.uid)
    await_selector(view, "#base-#{intro.uid}")

    assert html =~ "About us"
    assert has_element?(view, ".frontend-editor-heading h1", "Text")
    assert has_element?(view, "#base-#{intro.uid}")
    refute has_element?(view, "#base-#{container.uid}")
    refute has_element?(view, ".form-tabs")
    assert has_element?(view, ".blocks-wrapper.is-frontend-focus")

    assert has_element?(
             view,
             ".frontend-editor-open[href='/admin/pages/update/#{elem(page_id(view), 0)}?block=#{intro.uid}']"
           )
  end

  test "a block in a container renders with the container only on the way down",
       %{conn: conn, intro: intro, container: container, child: child} do
    {view, _html} = editor(conn, child.uid)
    await_selector(view, "#base-#{container.uid}")

    refute has_element?(view, "#base-#{intro.uid}")
    assert has_element?(view, ".base-block.focus-ancestor[data-block-uid='#{container.uid}']")
    assert has_element?(view, ".base-block.focus-target[data-block-uid='#{child.uid}']")
  end

  test "selecting another block of the entry moves the focus in place", %{conn: conn, intro: intro, child: child} do
    {view, _html} = editor(conn, intro.uid)
    pid = view.pid

    view |> element("#frontend-editor") |> render_hook("select", %{"uid" => child.uid})
    assert_patch(view, "/admin/frontend-edit?uid=#{child.uid}")

    assert view.pid == pid
    await_selector(view, ".base-block.focus-target[data-block-uid='#{child.uid}']")
    assert has_element?(view, "#frontend-editor[data-target='#{child.uid}']")
  end

  test "a block of another entry opens a new editor", %{conn: conn, intro: intro, current_user: user, module: module} do
    %{intro: other} = page_with_blocks(user, module: module, title: "Another page")
    {view, _html} = editor(conn, intro.uid)

    view |> element("#frontend-editor") |> render_hook("select", %{"uid" => other.uid})
    assert_redirect(view, "/admin/frontend-edit?uid=#{other.uid}")
  end

  test "an unknown block says so", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/admin/frontend-edit?uid=gone")
    assert has_element?(view, ".frontend-editor.is-unavailable [role=alert]")
    refute has_element?(view, ".frontend-edit-form")
  end

  test "nothing opens while frontend edit is switched off", %{conn: conn, intro: intro} do
    Application.put_env(:brando, FrontendEdit, enabled: false)
    {:ok, view, _html} = live(conn, "/admin/frontend-edit?uid=#{intro.uid}")
    assert has_element?(view, ".frontend-editor.is-unavailable")
  end

  test "preview HTML and save state go to the page", %{conn: conn, intro: intro, page: page} do
    {view, _html} = editor(conn, intro.uid)

    send(view.pid, {:frontend_edit, {:update_block, %{uid: intro.uid, rendered_html: "<p>x</p>", has_children: false}}})
    assert_push_event(view, "b:frontend-edit", %{type: "update_block", uid: uid, rendered_html: "<p>x</p>"})
    assert uid == intro.uid

    send(view.pid, {:frontend_edit, :dirty})
    assert_push_event(view, "b:frontend-edit", %{type: "dirty", dirty: true})
    assert has_element?(view, ".frontend-edit-status-dot.is-dirty")

    save(view)
    assert_push_event(view, "b:frontend-edit", %{type: "saved"}, 3_000)
    assert has_element?(view, ~s(.frontend-edit-status .lucide-circle-check))
    refute has_element?(view, "[data-testid=frontend-edit-stale]")

    # Saving went through the entry, rendering its stored HTML
    saved = Repo.get!(Page, page.id)
    assert saved.rendered_blocks =~ "Hello from the intro"
    assert saved.rendered_blocks_at
  end

  test "a save elsewhere marks the editor stale and refuses its save", %{conn: conn, intro: intro, page: page} do
    {view, _html} = editor(conn, intro.uid)

    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      Brando.Tenant.Topic.scoped("brando:mutations:#{inspect(Page)}"),
      {:mutation, Page, %{page | updated_at: NaiveDateTime.utc_now()}, :update}
    )

    await_selector(view, "[data-testid=frontend-edit-stale]")

    view |> form("##{@form}_form") |> render_submit()
    assert_push_event(view, "b:alert", %{type: "error"})
    refute_push_event(view, "b:frontend-edit", %{type: "saved"}, 200)

    view |> element("[data-testid=frontend-edit-stale] button") |> render_click()
    assert_push_event(view, "b:frontend-edit", %{type: "reload", uid: uid})
    assert uid == intro.uid
  end

  test "is present at the entry's admin form, as editing from the website", %{
    conn: conn,
    intro: intro,
    page: page,
    current_user: user
  } do
    {_view, _html} = editor(conn, intro.uid)

    presences = Brando.presence().list(Brando.Tenant.Topic.scoped("url:/admin/pages/update/#{page.id}"))
    assert %{metas: [%{frontend: true} | _]} = presences[to_string(user.id)]
  end

  test "a fragment says it is shared", %{conn: conn, current_user: user, module: module} do
    %{block: block} = fragment_with_block(user, module)
    {view, _html} = editor(conn, block.uid, "fragment_form")
    assert has_element?(view, "[data-testid=frontend-edit-shared]")
    # The full editor it opens is the fragment's own
    assert has_element?(view, ".frontend-editor-open[href^='/admin/pages/fragments/update/']")
  end

  defp page_id(view) do
    [href] = view |> render() |> Floki.parse_document!() |> Floki.attribute(".frontend-editor-open", "href")
    [_, id] = Regex.run(~r{/admin/pages/update/(\d+)}, href)
    {id}
  end

  describe "an entry field" do
    defp field_editor(conn, page),
      do: live_form(conn, "/admin/frontend-edit?field=#{Brando.FrontendEdit.Fields.key(Page, page.id, :title)}", @form)

    test "opens alone, without the entry's blocks", %{conn: conn, page: page, intro: intro} do
      {view, html} = field_editor(conn, page)

      assert has_element?(view, ".frontend-editor-heading h1", "Title")
      assert has_element?(view, "##{@form}_form input[name='page[title]']")
      refute has_element?(view, "##{@form}_form input[name='page[uri]']")
      refute has_element?(view, "#base-#{intro.uid}")
      assert html =~ "?field=title"
    end

    test "shows the value on the page as it changes, and saves only it", %{conn: conn, page: page} do
      {view, _html} = field_editor(conn, page)
      key = Brando.FrontendEdit.Fields.key(Page, page.id, :title)

      view
      |> element("##{@form}_form")
      |> render_change(%{"page" => %{"title" => "Fish & chips"}, "_target" => ["page", "title"]})

      assert_push_event(view, "b:frontend-edit", %{type: "dirty", dirty: true})
      assert_push_event(view, "b:frontend-edit", %{type: "entry_field", key: ^key, html: "Fish &amp; chips"})

      view |> form("##{@form}_form", %{"page" => %{"title" => "Fish & chips"}}) |> render_submit()
      assert_push_event(view, "b:submit", %{}, 2_000)
      view |> form("##{@form}_form", %{"page" => %{"title" => "Fish & chips"}}) |> render_submit()
      assert_push_event(view, "b:frontend-edit", %{type: "saved"}, 3_000)

      saved = Repo.get!(Page, page.id)
      assert saved.title == "Fish & chips"
      assert saved.uri == page.uri
      assert saved.rendered_blocks =~ "Hello from the intro"
    end

    test "a block of the same entry opens in the same editor", %{conn: conn, page: page, intro: intro} do
      {view, _html} = field_editor(conn, page)
      pid = view.pid

      view |> element("#frontend-editor") |> render_hook("select", %{"uid" => intro.uid})
      assert_patch(view, "/admin/frontend-edit?uid=#{intro.uid}")
      assert view.pid == pid
      await_selector(view, "#base-#{intro.uid}")
      refute has_element?(view, "##{@form}_form input[name='page[title]']")
    end

    @tag :capture_log
    test "an error in a field not shown here points to the full editor", %{conn: conn, page: page} do
      page |> Ecto.Changeset.change(uri: nil) |> Repo.update!()
      {view, _html} = field_editor(conn, page)

      view |> form("##{@form}_form", %{"page" => %{"title" => "Valid"}}) |> render_submit()
      assert_push_event(view, "b:submit", %{}, 2_000)
      view |> form("##{@form}_form", %{"page" => %{"title" => "Valid"}}) |> render_submit()
      assert_push_event(view, "b:frontend-edit", %{type: "save_failed"}, 3_000)
      assert has_element?(view, "[data-testid=frontend-edit-invalid] a[href='/admin/pages/update/#{page.id}']")
    end

    test "an unknown field says so", %{conn: conn, page: page} do
      {:ok, view, _html} = live(conn, "/admin/frontend-edit?field=Brando.Pages.Page:#{page.id}:nope")
      assert has_element?(view, ".frontend-editor.is-unavailable")
    end
  end
end
