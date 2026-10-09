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

      {:ok, _view, html} = live(c.conn, "/admin/pages/update/#{c.page.id}")

      assert title_value(html) == ["Stored title"]
      assert present?(html, ~s([phx-hook="Brando.BlockField"]))
      refute present?(html, ".form-load-state")
      refute present?(html, ".blocks-loading")
      refute present?(html, "#page_form_form[inert]")
      assert find(html, ".form-tool-save-button") |> Floki.attribute("disabled") == []
      assert present?(html, "#page_form-submit")
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

    test "keeps a value it was given before its blocks arrived, and saves with them", c do
      {:ok, view, html} = live(c.conn, "/admin/pages/update/#{c.page.id}")

      # A recovered form or another editor's value can arrive while the
      # blocks load; the form must not be rebuilt over it when they do. (The
      # blocks may also win the race here: the value must hold either way.)
      params = html |> form_params("#page_form_form") |> put_in(["page", "title"], "Recovered title")
      view |> element("#page_form_form") |> render_change(Map.put(params, "_target", ["page", "title"]))

      render_async(view, 5_000)
      html = await_selector(view, ~s([phx-hook="Brando.BlockField"]))
      assert title_value(html) == ["Recovered title"]

      assert {:ok, _path} = Brando.Test.save_form(view, Page)

      saved = Page |> Brando.Repo.get!(c.page.id) |> Brando.Repo.preload(:entry_blocks)
      assert saved.title == "Recovered title"
      assert length(saved.entry_blocks) == Form.light_block_limit() + 1
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

      for event <- ["push_submit", "push_submit_redirect", "push_submit_new", "push_submit_minor"],
          do: assert({:noreply, ^socket} = Form.handle_event(event, %{}, socket))
    end

    test "no recovery copy is captured", %{socket: socket} do
      socket = Phoenix.Component.assign(socket, :draft, %{initialized?: true, capture: nil})
      assert Form.Drafts.capture(socket, %{}) == socket
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
