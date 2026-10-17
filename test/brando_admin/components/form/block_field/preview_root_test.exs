defmodule BrandoAdmin.Components.Form.BlockField.PreviewRootTest do
  use Brando.ConnCase

  alias Brando.LivePreview
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.BlockField
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias Phoenix.Socket.Broadcast

  defp apply!(state, op) do
    {:ok, state} = Ops.apply_op(state, op)
    state
  end

  defp field_socket(ops) do
    user = Brando.Factory.insert(:random_user, avatar: nil)

    Phoenix.Component.assign(%Phoenix.LiveView.Socket{}, %{
      block_ops: ops,
      form_id: "page_form",
      block_field: :entry_blocks,
      entry_blocks: [],
      block_module: Brando.Pages.Page.Blocks,
      current_user: user,
      restored_blocks: %{}
    })
  end

  defp form_socket(key, title) do
    changeset = Ecto.Changeset.change(%Brando.Pages.Page{title: "Saved title"}, title: title)

    Phoenix.Component.assign(%Phoenix.LiveView.Socket{}, %{
      id: "page_form",
      form: Phoenix.Component.to_form(changeset),
      updated_entry_assocs: %{},
      frontend_edit: nil,
      live_preview_active?: true,
      live_preview_cache_key: key,
      preview_update: nil
    })
  end

  defp preview_key do
    key = "ROOT-#{System.unique_integer([:positive])}"
    Brando.endpoint().subscribe("live_preview:#{key}")
    key
  end

  # The child exists only in the store, inserted and never saved. A block
  # that does not read the entry keeps an old one, so the root renders with
  # the form's.
  test "a block that cannot render alone patches the root it belongs to, with the form's entry" do
    module = Brando.Factory.insert(:module, code: ~s(<p class="child">{{ entry.title }}</p>))

    ops =
      Ops.new([])
      |> apply!({:insert, "root", 0, %{"block" => %{"uid" => "root", "type" => "container", "active" => true}}})
      |> apply!(
        {:insert_child, "root", "child", 0,
         %{"uid" => "child", "type" => "module", "module_id" => module.id, "active" => true}}
      )

    assert {:ok, _} = BlockField.update(%{event: "preview_root", uid: "child"}, field_socket(ops))

    assert_received {:phoenix, :send_update,
                     {{Form, "page_form"}, %{event: "render_preview_root", uid: "root", root: root}}}

    key = preview_key()

    assert {:ok, _} =
             Form.update(%{event: "render_preview_root", uid: "root", root: root}, form_socket(key, "Unsaved title"))

    assert_received %Broadcast{event: "update_block", payload: %{uid: "root", rendered_html: html, has_children: false}}
    assert html =~ ~s(<p class="child">Unsaved title</p>)
    assert html =~ "[+:B<child>]"
  end

  test "a block the store does not know refreshes the whole preview" do
    assert {:ok, _} = BlockField.update(%{event: "preview_root", uid: "gone"}, field_socket(Ops.new([])))
    assert_received {:phoenix, :send_update, {{Form, "page_form"}, %{event: "update_live_preview"}}}
  end

  # Notes are numbered across the page, and a slot at the root has no block
  # of its own in the page
  test "notes and a slot at the root render the whole page instead" do
    key = preview_key()
    socket = form_socket(key, "T")
    note = ~s(<p>Text<sup data-footnote-uid="n1"></sup></p>)

    for params <- [
          %{event: "update_live_preview_block", rendered_html: note, uid: "B1", has_children?: false},
          %{
            event: "render_preview_root",
            uid: "S1",
            root: %Brando.Pages.Page.Blocks{block: %Brando.Content.Block{type: :slot}}
          }
        ] do
      assert {:ok, queued} = Form.update(params, socket)
      assert queued.assigns.preview_update.mode == :live_preview_update
    end

    refute_received %Broadcast{event: "update_block"}
    LivePreview.cleanup_cache(key)
  end

  # During recovery after a reconnect, the recovery renders once the
  # recovered input is in; a render before it would show the saved entry.
  test "a page missing patches gets the whole page again, except during recovery" do
    key = preview_key()
    socket = key |> form_socket("T") |> Phoenix.Component.assign(has_blocks?: true)
    lost = %{event: "live_preview_patches_lost", key: key}

    assert {:ok, queued} = Form.update(lost, socket)
    assert queued.assigns.preview_update.mode == :live_preview_full_rerender

    recovering = Phoenix.Component.assign(socket, :live_preview_recovery_pending?, true)
    assert {:ok, %{assigns: %{preview_update: nil}}} = Form.update(lost, recovering)
    assert {:ok, %{assigns: %{preview_update: nil}}} = Form.update(%{lost | key: "another"}, socket)
    LivePreview.cleanup_cache(key)
  end
end
