defmodule BrandoAdmin.FormEntryOpenTest do
  # Opening an entry (`Form.open_entry/1`). The entry is read before the
  # form's first render. Up to `Form.light_block_limit/0` blocks render with
  # it; with more, the fields come first, read-only beside block outlines,
  # and the blocks follow. Save, the recovery copies and the edit session
  # wait for them.
  use Brando.LiveCase

  alias Brando.Content.Blocks
  alias Brando.Factory
  alias Brando.Pages.Page
  alias BrandoAdmin.Components.Form

  setup %{current_user: user} do
    # Through the context, which clears the module cache a factory insert
    # would leave stale
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Paragraph"},
          namespace: %{"en" => "Content"},
          help_text: %{"en" => "Help"},
          code: "<p>Paragraph</p>"
        ),
        user
      )

    page = Factory.insert(:page, creator: user, title: "Stored title")
    {:ok, page: page, module: module}
  end

  defp add_blocks(page, module, user, count) do
    for _ <- 1..count//1, do: Brando.Test.insert_block(page, module, user: user)
  end

  defp find(html, selector), do: html |> Floki.parse_document!() |> Floki.find(selector)
  defp present?(html, selector), do: find(html, selector) != []

  defp title_value(html), do: html |> find("#page_form_form input[name='page[title]']") |> Floki.attribute("value")

  describe "a light entry" do
    test "opens complete in its first render, at the limit too", c do
      add_blocks(c.page, c.module, c.current_user, Form.light_block_limit())

      {:ok, view, html} = live(c.conn, "/admin/pages/update/#{c.page.id}")

      assert title_value(html) == ["Stored title"]
      assert present?(html, ~s([phx-hook="Brando.BlockField"]))
      refute present?(html, ".form-load-state")
      refute present?(html, ".blocks-loading")
      refute present?(html, "#page_form_form[inert]")
      assert find(html, ".form-tool-save-button") |> Floki.attribute("disabled") == []
      assert present?(html, "#page_form-submit")
      # An untouched entry has nothing to keep a recovery copy of
      refute_push_event(view, "b:draft-dirty", _, 100)
    end

    test "an entry without blocks opens at once", c do
      {:ok, _view, html} = live(c.conn, "/admin/pages/update/#{c.page.id}")

      assert title_value(html) == ["Stored title"]
      assert present?(html, ~s([phx-hook="Brando.BlockField"]))
      refute present?(html, ".form-load-state")
    end
  end

  describe "a heavy entry" do
    setup c do
      add_blocks(c.page, c.module, c.current_user, Form.light_block_limit() + 1)
      :ok
    end

    test "shows its fields first, read-only, and its blocks when they have loaded", c do
      {:ok, view, html} = live(c.conn, "/admin/pages/update/#{c.page.id}")
      count = Form.light_block_limit() + 1

      # The fields are real; the blocks are outlines
      assert title_value(html) == ["Stored title"]
      assert find(html, "h1[data-testid='entry-title']") |> Floki.text() == "Stored title"
      assert find(html, ".form-load-state") |> Floki.text() |> String.trim() == "Loading #{count} blocks"
      assert present?(html, ".form-load-progress")
      assert length(find(html, ".blocks-loading .sk-block")) == 4
      refute present?(html, ~s([phx-hook="Brando.BlockField"]))

      # Read-only, and nothing saves or keeps a recovery copy yet
      assert present?(html, "#page_form_form[inert]")
      assert present?(html, ".form-tab-customs[inert]")
      assert find(html, ".form-tool-save-button") |> Floki.attribute("disabled") != []
      assert find(html, "[data-testid='status-trigger']") |> Floki.attribute("disabled") != []
      refute present?(html, "#page_form-submit")
      refute present?(html, "#page_form-el[data-draft-enabled]")
      refute present?(html, "#page_form-save-state")

      render_async(view, 5_000)
      html = render(view)

      assert present?(html, ~s([phx-hook="Brando.BlockField"]))
      assert length(find(html, "[data-block-uid]")) >= count
      refute present?(html, ".form-load-state")
      refute present?(html, ".form-load-progress")
      refute present?(html, ".blocks-loading")
      refute present?(html, "#page_form_form[inert]")
      assert find(html, ".form-tool-save-button") |> Floki.attribute("disabled") == []
      assert present?(html, "#page_form-submit")
      assert present?(html, "#page_form-el[data-draft-enabled]")
      assert present?(html, "#page_form-save-state")
    end
  end

  # The blocks are held back (`config :brando, :form_load_gate`) so the test
  # can act on the form while they load, as an editor or a delivery could.
  describe "while a heavy entry's blocks are held back" do
    setup c do
      add_blocks(c.page, c.module, c.current_user, Form.light_block_limit() + 1)
      test = self()

      Application.put_env(:brando, :form_load_gate, fn key ->
        send(test, {:load_held, key, self()})

        receive do
          :release -> :ok
        after
          5_000 -> :ok
        end
      end)

      on_exit(fn -> Application.delete_env(:brando, :form_load_gate) end)
      :ok
    end

    defp open_held(c) do
      {:ok, view, html} = live(c.conn, "/admin/pages/update/#{c.page.id}")
      assert_receive {:load_held, :blocks_load, task}
      {view, html, task}
    end

    defp release(view, task) do
      send(task, :release)
      render_async(view, 5_000)
      await_selector(view, ~s([phx-hook="Brando.BlockField"]))
    end

    test "the tools a shortcut can still reach do nothing", c do
      {view, _html, task} = open_held(c)
      form = view |> with_target(cid_of(view, "#page_form_form"))

      for event <- ~w(open_live_preview open_live_preview_standalone toggle_preview_targets share_link store_revision),
          do: render_hook(form, event, %{})

      render_hook(form, "select_preview_target", %{"name" => "desktop"})
      assert render(view) =~ "form-load-state"

      html = release(view, task)
      refute html =~ "form-load-state"
    end

    test "⌘S before the blocks have loaded leaves Save and close as it was", c do
      {view, html, task} = open_held(c)
      form = view |> with_target(cid_of(view, "#page_form_form"))
      main = html |> form_params("#page_form_form") |> Plug.Conn.Query.encode()

      render_hook(form, "save_form", %{"stay" => true, "form" => main})
      refute_push_event(view, "b:submit", _, 100)

      release(view, task)
      assert {:ok, "/admin/pages"} = Brando.Test.save_form(view, Page)
    end

    test "keeps a value it was given before its blocks arrived, and saves with them", c do
      {view, html, task} = open_held(c)

      params = html |> form_params("#page_form_form") |> put_in(["page", "title"], "Recovered title")
      view |> element("#page_form_form") |> render_change(Map.put(params, "_target", ["page", "title"]))

      html = release(view, task)
      assert title_value(html) == ["Recovered title"]

      assert {:ok, _path} = Brando.Test.save_form(view, Page)

      saved = Page |> Brando.Repo.get!(c.page.id) |> Brando.Repo.preload(:entry_blocks)
      assert saved.title == "Recovered title"
      assert length(saved.entry_blocks) == Form.light_block_limit() + 1
    end

    test "a recovered edit gets a recovery copy as soon as the blocks have loaded", c do
      {view, html, task} = open_held(c)
      form = view |> with_target(cid_of(view, "#page_form_form"))

      params = html |> form_params("#page_form_form") |> put_in(["page", "title"], "Typed offline")
      render_hook(form, "recover_form", params)
      refute_push_event(view, "b:draft-dirty", _, 100)

      release(view, task)
      assert_push_event(view, "b:draft-dirty", %{id: "page_form"})
    end

    defp open_preview(view) do
      view |> element("button[phx-click=toggle_preview_targets]") |> render_click()
      view |> element("button.preview-choice", "Blocks") |> render_click()
      html = await_selector(view, "iframe[src*='__livepreview']")
      [key] = Regex.run(~r/__livepreview\?key=([A-Za-z0-9_-]+)/, html, capture: :all_but_first)
      Brando.endpoint().subscribe("live_preview:#{key}")
      on_exit(fn -> Brando.LivePreview.cleanup_cache(key) end)
      key
    end

    # A reconnect to the entry with its preview open: both recovery forms
    # arrive while the blocks still load.
    defp reconnect_with_preview(c) do
      {view, _html, task} = open_held(c)
      html = release(view, task)
      key = open_preview(view)
      captured = html |> recovery_params("#page_form_form") |> put_in(["page", "title"], "Recovered title")
      kill_live(view)

      {view, _html, task} = open_held(c)
      [target] = view |> render() |> Floki.parse_document!() |> Floki.attribute("#live-preview-recovery", "phx-target")

      view
      |> with_target(String.to_integer(target))
      |> render_hook("recover_live_preview_state", %{"live_preview" => %{"cache_key" => key}})

      view |> with_target(cid_of(view, "#page_form_form")) |> render_hook("recover_form", captured)
      {view, task}
    end

    test "a preview recovered while the blocks load renders once they have", c do
      {view, task} = reconnect_with_preview(c)

      # Past the preview's own render delay, with the blocks still loading
      Process.sleep(1_300)
      view |> with_target(cid_of(view, "#page_form_form")) |> render_hook("refresh_live_preview", %{})
      assert render(view) =~ "form-load-state"
      refute_receive %Phoenix.Socket.Broadcast{event: "rerender"}, 50

      release(view, task)
      assert_receive %Phoenix.Socket.Broadcast{event: "rerender", payload: %{html: html}}, 3_000
      assert html =~ "Recovered title"
    end

    test "the preview can be closed while the blocks load, but not switched", c do
      {view, task} = reconnect_with_preview(c)
      assert render(view) =~ "__livepreview"

      html = view |> element("button[phx-click=toggle_preview_targets]") |> render_click()
      choices = find(html, "button.preview-choice")
      assert choices != []
      assert Enum.all?(choices, &(Floki.attribute(&1, "disabled") != []))
      assert find(html, "button.preview-choice-close") |> Floki.attribute("disabled") == []

      view |> with_target(cid_of(view, "#page_form_form")) |> render_hook("open_live_preview", %{})
      refute render(view) =~ "__livepreview"

      html = release(view, task)
      refute html =~ "__livepreview"
      refute_receive %Phoenix.Socket.Broadcast{event: "rerender"}, 1_500
    end

    test "an asset delivered while the blocks load does not make a recovered edit look saved", c do
      image =
        Factory.insert(:image, creator: c.current_user, focal: %Brando.Images.Focal{x: 50, y: 50}, status: :processed)

      {view, html, task} = open_held(c)
      form = view |> with_target(cid_of(view, "#page_form_form"))

      params = html |> form_params("#page_form_form") |> put_in(["page", "title"], "Unsaved title")
      render_hook(form, "recover_form", params)
      send(view.pid, {:asset_ready, %{"kind" => "entry_field", "field" => "meta_image"}, image})
      render(view)

      release(view, task)

      # The asset goes again; the unsaved title stays, and is what a copy keeps
      Phoenix.LiveView.send_update(view.pid, Form,
        id: "page_form",
        event: "clear_entry_field_asset",
        field: :meta_image,
        path: []
      )

      main = view |> render() |> form_params("#page_form_form") |> Plug.Conn.Query.encode()
      render_hook(form, "draft_capture", %{"main" => main, "blocks" => %{}, "generation" => 5, "request_id" => 1})
      await_selector(view, "[data-testid=draft-status]")
      settle(view)

      assert [copy] = Brando.Drafts.list(Brando.Drafts.identity(Page, c.page.id, c.current_user.id))
      assert copy.payload["main"]["title"] == "Unsaved title"
    end

    test "keeps what was delivered to the entry while its blocks loaded", c do
      {view, _html, task} = open_held(c)

      Phoenix.LiveView.send_update(view.pid, Form,
        id: "page_form",
        event: "update_entry_relation",
        path: [:title],
        updated_relation: "Delivered title",
        update_entry: true
      )

      html = release(view, task)
      assert find(html, "h1[data-testid='entry-title']") |> Floki.text() == "Delivered title"
    end
  end

  # The blocks load too quickly in a test to click in between, so the form's
  # own handlers are called with the state they would meet.
  describe "while a heavy entry's blocks load" do
    setup do
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, blocks_ready?: false}}
      {:ok, socket: socket}
    end

    test "Save and its shortcut do nothing", %{socket: socket} do
      for event <- ["save", "save_form"],
          do: assert({:noreply, ^socket} = Form.handle_event(event, %{"form" => "page%5Btitle%5D=x"}, socket))

      assert {:noreply, ^socket} = Form.handle_event("save_form", %{"stay" => true, "form" => ""}, socket)

      for event <- ["push_submit", "push_submit_redirect", "push_submit_new", "push_submit_minor"],
          do: assert({:noreply, ^socket} = Form.handle_event(event, %{}, socket))
    end

    test "no recovery copy is captured", %{socket: socket} do
      socket = Phoenix.Component.assign(socket, :draft, %{initialized?: true, capture: nil})
      assert Form.Drafts.capture(socket, %{}) == socket
    end
  end

  describe "the recovery baseline" do
    defp form_assigns(view) do
      {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
      Enum.find(components, &(&1.module == Form and &1.id == "page_form")).assigns
    end

    test "is the entry as read until recovery starts, then lives in its state", c do
      {view, _html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")
      assigns = form_assigns(view)

      assert assigns.draft.initialized?
      assert assigns.opened_entry == nil
    end

    test "follows each save while recovery has not started" do
      opened = %Page{id: 1, title: "Opened"}
      saved = %Page{id: 1, title: "Saved"}
      socket = %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}, draft: nil, opened_entry: opened}}

      assert Form.Drafts.keep_baseline(socket, saved).assigns.opened_entry == saved

      started = Phoenix.Component.assign(socket, :draft, %{initialized?: true})
      assert Form.Drafts.keep_baseline(started, saved).assigns.opened_entry == nil
    end
  end

  test "the block count includes nested blocks", c do
    [root] = add_blocks(c.page, c.module, c.current_user, 1)

    for sequence <- 0..1 do
      c.module.id
      |> Blocks.build_module_block(c.current_user.id, nil, Page.Blocks, :module)
      |> Ecto.Changeset.put_change(:parent_id, root.id)
      |> Ecto.Changeset.put_change(:sequence, sequence)
      |> Brando.Repo.insert!()
    end

    assert Blocks.count_entry_blocks_by_field(Page, c.page.id) == %{blocks: 3}
    assert Blocks.count_entry_blocks(Page, c.page.id) == 3
    assert Blocks.count_entry_blocks(Page, 0) == 0
  end

  test "a reload shows the form as a skeleton until LiveView connects", c do
    html = c.conn |> get("/admin/pages/update/#{c.page.id}") |> html_response(200)

    assert present?(html, "#entry-skeleton.form-loading")
    assert find(html, "#entry-skeleton .form-load-state") |> Floki.text() |> String.trim() == "Opening"
    assert find(html, "#entry-skeleton .entry-breadcrumb") |> Floki.text() =~ "Pages"
    refute html =~ "Stored title"
  end

  test "a listing row carries what it shows while its entry opens", c do
    {:ok, _view, html} = live(c.conn, "/admin/pages")

    row = find(html, "#list-row-#{c.page.id}")
    assert row |> Floki.find(".entry-opening") |> Floki.text() == "Opening"
    assert row |> Floki.find(".list-row-progress") != []
  end
end
