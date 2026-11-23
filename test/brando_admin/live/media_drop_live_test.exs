defmodule BrandoAdmin.MediaDropLiveTest do
  # Files dropped on a multi block whose module has a `media_drop` (#3491),
  # through the page editor: the block makes one child per file, in order,
  # through the op "add child" emits, and names each child's ref field for the
  # browser to hand the file to. A failed upload takes its child away again.
  # The browser side (MediaDrop, UploadTrigger) is covered by
  # e2e/playwright/tests/blocks/block-multi-media-drop.spec.js.
  use Brando.LiveCase

  alias Brando.Content
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.BlockField

  defp create_module(user, attrs) do
    {:ok, module} =
      %{
        name: %{"en" => "Card"},
        namespace: %{"en" => "general"},
        help_text: %{"en" => "Card"},
        class: "card-#{System.unique_integer([:positive])}",
        code: "{% ref refs.visual %}",
        refs: []
      }
      |> Map.merge(attrs)
      |> Content.create_module(user)

    module
  end

  defp ref(name, type, data \\ %{}),
    do: %{name: name, uid: Brando.Utils.generate_uid(), data: %{type: type, data: data}}

  setup %{current_user: user} do
    # Videos upload to the site here, so a media ref takes them too
    put_test_env(Brando.Videos, default_config: %Brando.Type.VideoConfig{allow_uploads: true, upload_strategy: :local})

    row =
      create_module(user, %{
        name: %{"en" => "Image row"},
        code: "{{ content }}",
        multi: true,
        uid: "row",
        media_drop_child: "card",
        media_drop_ref: "visual"
      })

    create_module(user, %{
      name: %{"en" => "Image card"},
      uid: "card",
      parent_id: row.id,
      sequence: 0,
      refs: [ref("visual", "media", %{available_blocks: ["picture", "video"]})]
    })

    page = Factory.insert(:page, creator: user)
    %{row: row, page: page}
  end

  defp open(conn, page) do
    tab = %{"brando_tab" => "media-drop", "brando_tab_seq" => System.unique_integer([:monotonic, :positive])}
    {view, _html} = conn |> put_connect_params(tab) |> live_form("/admin/pages/update/#{page.id}")
    await(fn -> component(view, BrandoAdmin.Components.Form, "page_form").assigns.tab_editing? end)
    view
  end

  defp component(view, module, id \\ nil) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.module == module and (is_nil(id) or &1.id == id)))
  end

  defp row_block(view, uid) do
    {:ok, components} = Phoenix.LiveView.Debug.live_components(view.pid)
    Enum.find(components, &(&1.module == Block and &1.assigns[:uid] == uid))
  end

  defp root_uid(view) do
    [uid] = component(view, BlockField).assigns.root_order
    uid
  end

  defp await(fun, tries \\ 100) do
    cond do
      fun.() -> :ok
      tries == 0 -> flunk("never came true")
      true -> Process.sleep(20) && await(fun, tries - 1)
    end
  end

  defp drop(view, uid, kinds) do
    view
    |> with_target(cid_of(view, "#block-#{uid}-media-drop"))
    |> render_hook("media_drop", %{"files" => Enum.map(kinds, &%{"kind" => &1, "filename" => "#{&1}.file"})})
  end

  defp store_children(view, uid) do
    component(view, BlockField).assigns
    |> Map.fetch!(:block_ops)
    |> Map.fetch!(:child_order)
    |> Map.get(uid, [])
  end

  test "makes one child per dropped file, in order, and names the field each file goes to",
       %{conn: conn, page: page, row: row, current_user: user} do
    Brando.Test.insert_block(page, row, user: user)
    view = open(conn, page)
    uid = root_uid(view)

    assert has_element?(view, "#block-#{uid}-media-drop")

    drop(view, uid, ~w(image video image))
    assert_reply(view, %{children: [first, second, third]})

    assert row_block(view, uid).assigns.block_list == [first.uid, second.uid, third.uid]
    assert store_children(view, uid) == [first.uid, second.uid, third.uid]

    # A media ref takes the file's type: picture, video, picture
    assert first.field =~ ~r/^block-.+-upload$/
    refute first.field =~ "video"
    assert second.field =~ ~r/^block-.+-video-upload$/

    for child <- [first, second, third], do: assert(has_element?(view, "##{child.field}"))
  end

  test "a failed upload takes its child away again, and only a child made for a drop",
       %{conn: conn, page: page, row: row, current_user: user} do
    Brando.Test.insert_block(page, row, user: user)
    view = open(conn, page)
    uid = root_uid(view)

    drop(view, uid, ~w(image image))
    assert_reply(view, %{children: [first, second]})

    view
    |> with_target(cid_of(view, "#block-#{uid}-media-drop"))
    |> render_hook("media_drop_failed", %{"uid" => first.uid, "error" => "Too large"})

    assert_push_event(view, "b:alert", %{title: _, message: "Too large", type: "error"})
    assert row_block(view, uid).assigns.block_list == [second.uid]
    assert store_children(view, uid) == [second.uid]
    refute has_element?(view, "##{first.field}")

    # A uid that is not one of its dropped children changes nothing
    view
    |> with_target(cid_of(view, "#block-#{uid}-media-drop"))
    |> render_hook("media_drop_failed", %{"uid" => "not-dropped"})

    assert row_block(view, uid).assigns.block_list == [second.uid]
  end

  test "a file of a kind the ref does not take makes no child", %{conn: conn, page: page, current_user: user} do
    row = create_module(user, %{name: %{"en" => "Photo row"}, code: "{{ content }}", multi: true, uid: "photo-row"})

    create_module(user, %{uid: "photo-card", parent_id: row.id, refs: [ref("photo", "picture")]})

    {:ok, row} =
      row
      |> Content.Module.changeset(%{media_drop_child: "photo-card", media_drop_ref: "photo"}, user)
      |> Brando.Repo.update()

    Brando.Test.insert_block(page, row, user: user)
    view = open(conn, page)
    uid = root_uid(view)

    assert Map.keys(row_block(view, uid).assigns.media_drop.kinds) == [:image]

    drop(view, uid, ~w(image video))
    assert_reply(view, %{children: []})
    assert row_block(view, uid).assigns.block_list == []
  end

  test "a multi block without media_drop shows no drop zone", %{conn: conn, page: page, current_user: user} do
    row = create_module(user, %{name: %{"en" => "Plain row"}, code: "{{ content }}", multi: true, uid: "plain-row"})
    create_module(user, %{uid: "plain-card", parent_id: row.id, refs: [ref("visual", "media")]})
    Brando.Test.insert_block(page, row, user: user)
    view = open(conn, page)

    refute has_element?(view, ".block-media-drop")
  end
end
