defmodule BrandoAdmin.TrashedModuleInUseLiveTest do
  # The editor is told when a save or restore would bring a module in the
  # trash back into use (#3902): the entry form keeps what was typed and
  # names the module and the block, and the trash names the module.
  use Brando.LiveCase

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Block
  alias Brando.Pages.Fragment
  alias Brando.Pages.Page
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.BlockField
  alias Phoenix.Socket.Broadcast

  @block_field "page_form-blocks-blocks"

  setup %{current_user: user} do
    put_test_env(:authorization_mode, :legacy)
    put_test_env(:tenancy_mode, :none)
    Brando.endpoint().subscribe("user:#{user.id}")

    {:ok, module} =
      Brando.Content.create_module(
        %{name: %{"en" => "Teaser"}, namespace: "general", help_text: "Help", class: "teaser", code: "<p>teaser</p>"},
        user
      )

    {:ok, module: module, page: Factory.insert(:page, creator: user, title: "Om oss")}
  end

  test "a save adding a block of a module put in the trash meanwhile says so and keeps the form", c do
    {view, _html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")

    Phoenix.LiveView.send_update(view.pid, BlockField,
      id: @block_field,
      event: "insert_block",
      sequence: 0,
      module_id: c.module.id
    )

    await_selector(view, "[data-block-uid]")

    {:ok, _} = Brando.Content.delete_module(c.module.id, c.current_user)
    save(view)

    assert_receive %Broadcast{event: "toast", payload: %{payload: message, level: :error}}, 5_000
    assert message =~ "Teaser"
    assert message =~ Brando.Content.module_in_trash_message(%{module: %{"en" => "Teaser"}, block: {:root, 1}})
    assert Process.alive?(view.pid)
    refute form_assigns(view).processing
    assert Repo.aggregate(from(b in Block, where: b.module_id == ^c.module.id), :count) == 0
  end

  describe "the trash" do
    test "names the module a page's block uses when it refuses its restore", c do
      put_block!(Page, c.page, c.module)
      {:ok, _} = Brando.Pages.delete_page(c.page.id, c.current_user)
      {:ok, _} = Brando.Content.delete_module(c.module.id, c.current_user)

      assert_undelete_names_module(c)
    end

    test "names the module of a block in a fragment trashed with the page", c do
      fragment = Factory.insert(:fragment, creator: c.current_user, page_id: c.page.id, key: "cascaded")
      put_block!(Fragment, fragment, c.module)
      {:ok, _} = Brando.Pages.delete_page(c.page.id, c.current_user, fragments: :delete)
      {:ok, _} = Brando.Content.delete_module(c.module.id, c.current_user)

      assert_undelete_names_module(c)
      assert Repo.get!(Fragment, fragment.id).deleted_at
    end
  end

  # #3923: where the editor activates a revision or duplicates an entry
  test "the revisions drawer names the module when it refuses a revision that would bring back its block", c do
    put_block!(Page, c.page, c.module)
    {:ok, old} = Brando.Revisions.create_revision(c.page, c.current_user)
    Repo.delete_all(from(j in Page.Blocks, where: j.entry_id == ^c.page.id))
    {:ok, _} = Brando.Revisions.create_revision(c.page, c.current_user)
    {:ok, _} = Brando.Content.delete_module(c.module.id, c.current_user)

    {view, _html} = live_form(c.conn, "/admin/pages/update/#{c.page.id}")
    drawer = view |> cid_of("#page_form-revisions-drawer-tab-activity") |> then(&with_target(view, &1))
    drawer |> render_hook("activate_revision", %{"value" => to_string(old.revision)})

    assert_push_event(view, "b:alert", %{type: "error", message: message})
    assert message == Brando.Content.module_in_trash_message(%{module: %{"en" => "Teaser"}, block: {:root, 1}}, :revision)
    assert message =~ "Teaser"
    assert Repo.aggregate(from(j in Page.Blocks, where: j.entry_id == ^c.page.id), :count) == 0
  end

  test "the listing names the module when it refuses to duplicate an entry holding its block", c do
    put_block!(Page, c.page, c.module)
    Repo.soft_delete!(c.module)
    pages = Repo.aggregate(Page, :count)

    {:ok, view, _html} = live(c.conn, "/admin/pages")
    render_hook(view, "duplicate_entry", %{"id" => to_string(c.page.id)})

    assert_receive %Broadcast{event: "toast", payload: %{payload: message}}, 2_000
    assert message == Brando.Content.module_in_trash_message(%{module: %{"en" => "Teaser"}, block: {:root, 1}}, :duplicate)
    assert Repo.aggregate(Page, :count) == pages
  end

  defp assert_undelete_names_module(c) do
    {:ok, view, _html} = live(c.conn, "/admin/pages?status=deleted")
    render_hook(view, "undelete_entry", %{"id" => to_string(c.page.id)})

    assert_receive %Broadcast{event: "toast", payload: %{payload: message}}, 2_000
    assert message == Brando.Content.module_in_trash_message(%{module: %{"en" => "Teaser"}})
    assert message =~ "Teaser"
    assert Repo.get!(Page, c.page.id).deleted_at
  end

  # A save is two submits: the first collects the blocks, the second writes
  defp save(view) do
    view |> form("#page_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 5_000)
    view |> form("#page_form_form") |> render_submit()
  end

  defp form_assigns(view) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.module == Form and &1.id == "page_form")).assigns
  end

  # Saved while the module was live
  defp put_block!(schema, entry, module) do
    block =
      Repo.insert!(%Block{
        uid: "block-#{System.unique_integer([:positive])}",
        source: "Elixir.#{inspect(schema)}.Blocks",
        type: :module,
        module_id: module.id
      })

    Repo.insert_all(Module.concat(schema, "Blocks"), [%{entry_id: entry.id, block_id: block.id, sequence: 0}])
  end
end
