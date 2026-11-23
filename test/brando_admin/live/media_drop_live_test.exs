defmodule BrandoAdmin.MediaDropLiveTest do
  # Files dropped on a multi block whose module has a `media_drop` (#3491),
  # through the page editor: the block makes one child per file, in order,
  # through the op "add child" emits, and names each child's ref field for the
  # browser to hand the file to. A failed upload takes its child away again.
  # The browser side (MediaDrop, UploadTrigger) is covered by
  # e2e/playwright/tests/blocks/block-multi-media-drop.spec.js.
  use Brando.LiveCase

  alias Brando.Content
  alias BrandoAdmin.Components.Assets.MediaField
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

  defp settle(view, child, params) do
    view
    |> with_target(cid_of(view, "#block-field-blocks"))
    |> render_hook("media_drop_settled", Map.merge(%{"uid" => child.uid, "token" => child.token}, params))
  end

  defp field_id(view), do: component(view, BlockField).id

  # Another editor's change to the child, or one typed here, as the store takes it
  defp edit(view, uid, description) do
    Phoenix.LiveView.send_update(view.pid, BlockField,
      id: field_id(view),
      event: "block_op",
      op: {:set_field, uid, ["description"], description, nil}
    )

    render(view)
  end

  test "a failed upload takes its child away again, and only the upload handed to it",
       %{conn: conn, page: page, row: row, current_user: user} do
    Brando.Test.insert_block(page, row, user: user)
    view = open(conn, page)
    uid = root_uid(view)

    drop(view, uid, ~w(image image))
    assert_reply(view, %{children: [first, second]})

    # Another token is not the upload handed to the child
    settle(view, %{first | token: "other"}, %{"failed" => true, "error" => "Too large"})
    assert row_block(view, uid).assigns.block_list == [first.uid, second.uid]

    settle(view, first, %{"failed" => true, "error" => "Too large"})

    assert_push_event(view, "b:alert", %{title: _, message: "Too large", type: "error"})
    await(fn -> row_block(view, uid).assigns.block_list == [second.uid] end)
    assert store_children(view, uid) == [second.uid]
    refute has_element?(view, "##{first.field}")

    # Settled once, a child is no longer tracked
    settle(view, first, %{"failed" => true})
    assert component(view, BlockField).assigns.media_drop_pending |> Map.keys() == [second.uid]
  end

  test "a child changed since the drop stays when its upload fails, and the editor is told",
       %{conn: conn, page: page, row: row, current_user: user} do
    Brando.Test.insert_block(page, row, user: user)
    view = open(conn, page)
    uid = root_uid(view)

    drop(view, uid, ~w(video))
    assert_reply(view, %{children: [child]})

    edit(view, child.uid, "Typed while it uploads")
    settle(view, child, %{"failed" => true, "error" => "Too large"})

    assert_push_event(view, "b:alert", %{message: message, type: "error"})
    assert message =~ "Too large"
    assert row_block(view, uid).assigns.block_list == [child.uid]
    assert store_children(view, uid) == [child.uid]
    assert component(view, BlockField).assigns.media_drop_pending == %{}
  end

  test "a child whose upload succeeded is no longer taken away by a later failure",
       %{conn: conn, page: page, row: row, current_user: user} do
    Brando.Test.insert_block(page, row, user: user)
    view = open(conn, page)
    uid = root_uid(view)

    drop(view, uid, ~w(image))
    assert_reply(view, %{children: [child]})

    settle(view, child, %{"failed" => false})
    settle(view, child, %{"failed" => true, "error" => "Too large"})

    assert row_block(view, uid).assigns.block_list == [child.uid]
    refute_push_event(view, "b:alert", %{message: "Too large"})
  end

  test "a child moved to another block during its upload is taken away there when it fails",
       %{conn: conn, page: page, row: row, current_user: user} do
    Brando.Test.insert_block(page, row, user: user)
    Brando.Test.insert_block(page, row, user: user)
    view = open(conn, page)
    [from, to] = component(view, BlockField).assigns.root_order

    drop(view, from, ~w(image))
    assert_reply(view, %{children: [child]})

    view
    |> with_target(cid_of(view, "#block-field-blocks"))
    |> render_hook("outline_reposition", %{
      "uid" => child.uid,
      "old" => 0,
      "new" => 0,
      "from" => %{"parentUid" => from},
      "to" => %{"parentUid" => to}
    })

    await(fn -> row_block(view, to).assigns.block_list == [child.uid] end)

    settle(view, child, %{"failed" => true})
    await(fn -> row_block(view, to).assigns.block_list == [] end)
    assert store_children(view, to) == []
    assert row_block(view, from).assigns.block_list == []
  end

  # A provider upload ends when the move takes its hook off the page. Before,
  # nothing said so, and a later failed upload into the field took the child
  # away as if it were the drop's.
  test "a child whose upload stopped when it was moved is taken away, and the editor is told why",
       %{conn: conn, page: page, row: row, current_user: user} do
    Brando.Test.insert_block(page, row, user: user)
    view = open(conn, page)
    uid = root_uid(view)

    drop(view, uid, ~w(video))
    assert_reply(view, %{children: [child]})

    settle(view, child, %{"failed" => true, "aborted" => true})

    assert_push_event(view, "b:alert", %{message: message, type: "error"})
    assert message != ""
    await(fn -> row_block(view, uid).assigns.block_list == [] end)
  end

  test "more files than the upload manager takes at once: the rest are said and make no child",
       %{conn: conn, page: page, row: row, current_user: user} do
    Brando.Test.insert_block(page, row, user: user)
    view = open(conn, page)
    uid = root_uid(view)
    max = BrandoAdmin.UploadManager.max_entries()

    drop(view, uid, List.duplicate("image", max + 2))
    assert_reply(view, %{children: children})

    assert length(children) == max
    assert_push_event(view, "b:alert", %{html: html, type: "error"})
    assert length(Regex.scan(~r/<li>/, html)) == 2
  end

  test "a synchronized translation shows no zone, and refuses a drop with the alert a refused file has",
       %{conn: conn, row: row, current_user: user} do
    put_test_env(Brando.Pages.Page, translatable: [mode: :synchronized])
    source = Factory.insert(:page, title: "Om oss", uri: "om-oss", language: :no, creator: user)
    Brando.Test.insert_block(source, row, user: user)
    {:ok, target} = Brando.Translations.create_target(Brando.Pages.Page, source.id, :en, user)

    view = open(conn, target)
    uid = root_uid(view)
    refute has_element?(view, "#block-#{uid}-media-drop")

    view
    |> with_target(row_block(view, uid).cid)
    |> render_hook("media_drop", %{"files" => [%{"kind" => "image", "filename" => "photo.jpg"}]})

    assert_reply(view, %{children: []})
    assert_push_event(view, "b:alert", %{html: html, type: "error"})
    assert html =~ "photo.jpg"
    assert row_block(view, uid).assigns.block_list == []
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
    assert_push_event(view, "b:alert", %{html: html, type: "error"})
    assert html =~ "video.file"
    assert row_block(view, uid).assigns.block_list == []
  end

  # Only the way down to the focused block renders, so a new child would show
  # no field for its file: the zone and the event both read this
  test "takes no files while the block is an ancestor of the focused block, or follows a source" do
    media_drop = %{kinds: %{image: %{}}}

    assert Block.media_drop_open(%{media_drop: media_drop, source_locked: false, focus_role: nil}) == media_drop
    assert Block.media_drop_open(%{media_drop: media_drop, source_locked: false, focus_role: :target}) == media_drop
    assert Block.media_drop_open(%{media_drop: media_drop, source_locked: false, focus_role: :ancestor}) == nil
    assert Block.media_drop_open(%{media_drop: media_drop, source_locked: true, focus_role: nil}) == nil
  end

  # The browser refuses a file before a child is made exactly when the upload
  # would: "*" takes any type there, as `Brando.Uploads` takes it
  test "a ref whose config takes any type advertises no type list" do
    images = Application.get_env(:brando, Brando.Images, [])
    any = %Brando.Type.ImageConfig{Brando.Type.ImageConfig.default_config() | allowed_mimetypes: ["*"]}
    put_test_env(Brando.Images, Keyword.put(images, :default_config, any), global: true)

    assert %{mimetypes: nil, extensions: extensions} = MediaField.upload_policy(:image, "default")
    assert ".jpg" in extensions

    jpeg = %{any | allowed_mimetypes: ["image/jpeg"]}
    put_test_env(Brando.Images, Keyword.put(images, :default_config, jpeg), global: true)
    assert %{mimetypes: ["image/jpeg"]} = MediaField.upload_policy(:image, "default")
  end

  test "a multi block without media_drop shows no drop zone", %{conn: conn, page: page, current_user: user} do
    row = create_module(user, %{name: %{"en" => "Plain row"}, code: "{{ content }}", multi: true, uid: "plain-row"})
    create_module(user, %{uid: "plain-card", parent_id: row.id, refs: [ref("visual", "media")]})
    Brando.Test.insert_block(page, row, user: user)
    view = open(conn, page)

    refute has_element?(view, ".block-media-drop")
  end
end
