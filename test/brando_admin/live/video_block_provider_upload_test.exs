defmodule BrandoAdmin.VideoBlockProviderUploadTest do
  @moduledoc """
  A video ref and a video var whose config uploads to a provider (Mux, Bunny,
  Cloudflare, Vimeo) take an upload themselves, as a video field does: Upload
  and a drop hand the file to the provider's hook rendered beside them, which
  asks the ref or var for each upload's destination and moves the bytes
  straight to the provider. The video picker, which knows the editor, creates
  the video. Before, they offered no Upload and refused a drop with "Use
  Select video to upload a video with this provider".
  """
  use Brando.LiveCase

  import Brando.EditSessionEditors, only: [await: 1]

  alias Brando.Content.Block
  alias Brando.Pages.Page
  alias Brando.ProposalFixtures
  alias Brando.Videos.Uploaders.Bunny

  @guid "6f2c1a3e-1111-2222-3333-444455556666"

  setup %{current_user: user} do
    put_test_env(:default_video_upload_strategy, :bunny)

    put_test_env(Bunny,
      api_key: "key",
      library_id: "77",
      cdn_hostname: "vz-1.b-cdn.net",
      webhook_secret: "whsec",
      req_options: [plug: {Req.Test, Bunny}]
    )

    Req.Test.set_req_test_to_shared()
    on_exit(fn -> Req.Test.set_req_test_to_private() end)

    Req.Test.stub(Bunny, fn %{method: "POST", request_path: "/library/77/videos"} = conn ->
      Req.Test.json(conn, %{"guid" => @guid, "videoLibraryId" => 77, "title" => "Clip"})
    end)

    {:ok, page_with_video_ref_and_var(user)}
  end

  describe "a video ref" do
    test "offers Upload, through the provider's hook", ctx do
      view = open(ctx)
      media = "#block-#{ctx.ref_uid}-video-upload"

      assert has_element?(view, ~s(#{media}[data-upload-enabled="true"][data-video-hook-id="#{ref_hook_id(ctx)}"]))
      assert has_element?(view, "#{media} .upload-trigger")
      assert has_element?(view, ~s(##{ref_hook_id(ctx)}[phx-hook="Brando.BunnyUploader"]))
    end

    test "an upload is created by the editor, with the ref's config, and set on the ref once it is up", ctx do
      view = open(ctx)
      video_id = request_upload(view, "##{ref_hook_id(ctx)}", "ref-1")

      video = Repo.get!(Brando.Videos.Video, video_id)
      assert video.type == :bunny
      assert video.config_target == "default"
      assert video.creator_id == ctx.user.id

      refute ref_video_id(view) == to_string(video_id)

      complete_upload(view, "##{ref_hook_id(ctx)}", "ref-1", video_id)
      await(fn -> ref_video_id(view) == to_string(video_id) end)
    end

    test "an upload that finishes after another video was picked leaves the pick", ctx do
      picked = Factory.insert(:video)
      view = open(ctx)
      hook = "##{ref_hook_id(ctx)}"
      video_id = request_upload(view, hook, "ref-late")

      view |> with_target(cid_of(view, hook)) |> render_hook("select_video", %{"id" => picked.id})
      await(fn -> ref_video_id(view) == to_string(picked.id) end)

      complete_upload(view, hook, "ref-late", video_id)
      assert ref_video_id(view) == to_string(picked.id)
      assert Repo.get(Brando.Videos.Video, video_id)
    end
  end

  describe "a video var" do
    test "offers Upload, through the provider's hook", ctx do
      view = open(ctx)
      hook = var_hook(view)

      assert has_element?(view, ~s([data-video-hook-id="#{hook}"][data-upload-enabled="true"]))
      assert has_element?(view, ~s(##{hook}[phx-hook="Brando.BunnyUploader"]))
    end

    test "an upload is created by the editor, with the var's config, and set on the var once it is up", ctx do
      view = open(ctx)
      hook = "#" <> var_hook(view)
      video_id = request_upload(view, hook, "var-1")

      video = Repo.get!(Brando.Videos.Video, video_id)
      assert video.config_target == "default"
      assert video.creator_id == ctx.user.id

      complete_upload(view, hook, "var-1", video_id)
      await(fn -> var_video_id(view) == to_string(video_id) end)
    end

    test "an upload that finishes after another video was picked leaves the pick", ctx do
      picked = Factory.insert(:video)
      view = open(ctx)
      hook = "#" <> var_hook(view)
      video_id = request_upload(view, hook, "var-late")

      view |> with_target(cid_of(view, hook)) |> render_hook("select_video", %{"id" => picked.id})
      await(fn -> var_video_id(view) == to_string(picked.id) end)

      complete_upload(view, hook, "var-late", video_id)
      assert var_video_id(view) == to_string(picked.id)
      assert Repo.get(Brando.Videos.Video, video_id)
    end

    # The block's settings render only while its config modal is open, and
    # closing it would take the hook, and the transfer, with it. Such a var
    # uploads through the video picker, whose hook stays.
    test "in the block's settings it uploads through the picker", ctx do
      view = open(ctx)
      modal = "#block-#{ctx.block_uid}_config"

      view
      |> element(~s(button.menu-item[phx-click="open_block_config"][phx-value-uid="#{ctx.block_uid}"]))
      |> render_click()

      assert has_element?(view, ~s(#{modal} [id$="-video-media"][data-upload-enabled="false"]))
      refute has_element?(view, ~s(#{modal} [id$="-video-uploader"]))
    end
  end

  # An entry's own vars (`Input.Vars`) have no block to tell: a var's value
  # goes to the form with the `b:validate` push.
  describe "an entry's video var" do
    setup %{user: user} do
      page =
        Factory.insert(:page,
          creator: user,
          title: "Reel",
          uri: "reel",
          vars: [
            %Brando.Content.Var{type: :video, key: "hero", label: "Hero", sequence: 0, creator_id: user.id},
            %Brando.Content.Var{type: :video, key: "outro", label: "Outro", sequence: 1, creator_id: user.id}
          ]
        )

      {:ok, entry: page}
    end

    test "offers Upload, and takes the upload once it is up", ctx do
      view = open_entry(ctx)
      hook = "#page_vars_0-video-uploader"

      assert has_element?(view, ~s([data-video-hook-id="page_vars_0-video-uploader"][data-upload-enabled="true"]))
      assert has_element?(view, ~s(#{hook}[phx-hook="Brando.BunnyUploader"]))

      video_id = request_upload(view, hook, "entry-1")
      assert Repo.get!(Brando.Videos.Video, video_id).creator_id == ctx.user.id

      complete_upload(view, hook, "entry-1", video_id)

      assert_push_event(view, "b:validate", %{target: "page[vars][0][video_id]", value: ^video_id})
      assert entry_var_video_id(view, 0) == to_string(video_id)
    end

    test "changed to another type and back, it offers Upload again", ctx do
      view = open_entry(ctx)

      change_entry(view, %{"vars" => %{"0" => %{"type" => "string"}}})
      refute has_element?(view, "#page_vars_0-video-uploader")

      change_entry(view, %{"vars" => %{"0" => %{"type" => "video"}}})
      assert has_element?(view, ~s(#page_vars_0-video-uploader[phx-hook="Brando.BunnyUploader"]))
    end

    # Its component is the row's: moved, the row shows the other var, which
    # the upload isn't for.
    test "an upload that finishes after its var was moved sets neither", ctx do
      view = open_entry(ctx)
      row = cid_of(view, "#page_vars_0-video-uploader")
      video_id = request_upload(view, "#page_vars_0-video-uploader", "entry-moved")

      change_entry(view, %{"sort_var_ids" => ["1", "0"]})
      assert has_element?(view, ~s(input[name="page[vars][0][key]"][value="outro"]))

      view
      |> with_target(row)
      |> render_hook("video_upload_complete", %{"request_ref" => "entry-moved", "video_id" => video_id})

      refute_push_event(view, "b:validate", %{target: "page[vars][" <> _})
      assert entry_var_video_id(view, 0) in [nil, ""]
      assert entry_var_video_id(view, 1) in [nil, ""]
    end
  end

  test "a refused upload is reported to the hook", ctx do
    view = open(ctx)

    view
    |> with_target(cid_of(view, "##{ref_hook_id(ctx)}"))
    |> render_hook("get_video_upload_url", %{
      "request_ref" => "ref-2",
      "filename" => "notes.txt",
      "size" => 1_000,
      "mime_type" => "text/plain"
    })

    assert_push_event(view, "video_upload_url_error", %{request_ref: "ref-2", error: error})
    assert is_binary(error)
    assert Process.alive?(view.pid)
  end

  test "without the provider's credentials neither can upload", ctx do
    put_test_env(Bunny, [])
    view = open(ctx)

    assert has_element?(view, ~s(#block-#{ctx.ref_uid}-video-upload[data-upload-enabled="false"]))
    refute has_element?(view, "##{ref_hook_id(ctx)}")
    refute has_element?(view, ~s([id$="-video-uploader"]))
  end

  # The picker creates the upload, and the Globals screen has none: a global
  # set's video var keeps choosing from the library.
  test "a global set's video var doesn't take a provider upload", ctx do
    Factory.insert(:global_set,
      label: "Films",
      key: "films",
      vars: [%Brando.Content.Var{type: :video, key: "intro", label: "Intro", creator_id: ctx.user.id}]
    )

    {:ok, globals, _html} = live(ctx.conn, "/admin/globals")
    render_async(globals)

    assert has_element?(globals, ~s([id$="-video-media"][data-upload-enabled="false"]))
    refute has_element?(globals, ~s([id$="-video-uploader"]))
  end

  defp request_upload(view, hook, request_ref) do
    view
    |> with_target(cid_of(view, hook))
    |> render_hook("get_video_upload_url", %{
      "request_ref" => request_ref,
      "filename" => "clip.mp4",
      "size" => 1_000,
      "mime_type" => "video/mp4"
    })

    assert_push_event(view, "video_upload_url_ready", %{request_ref: ^request_ref, video_id: video_id, tus_auth: tus_auth})

    assert tus_auth.video_id == @guid
    video_id
  end

  defp complete_upload(view, hook, request_ref, video_id) do
    view
    |> with_target(cid_of(view, hook))
    |> render_hook("video_upload_complete", %{"request_ref" => request_ref, "video_id" => video_id})
  end

  defp ref_hook_id(ctx), do: "block-#{ctx.ref_uid}-video-uploader"

  # The var's hook: the uploader that isn't the ref's
  defp var_hook(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.attribute(~s{[id$="-video-uploader"]:not([id^="block-"])}, "id")
    |> List.first()
  end

  defp ref_video_id(view), do: input_value(view, ~s(input[name$="[refs][0][video_id]"]))
  defp var_video_id(view), do: input_value(view, ~s(input[name$="[vars][0][video_id]"]))

  defp input_value(view, selector) do
    view |> render() |> Floki.parse_document!() |> Floki.attribute(selector, "value") |> List.first()
  end

  defp open_entry(%{conn: conn, entry: page}) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    view
  end

  defp change_entry(view, params) do
    view |> element("#page_form_form") |> render_change(%{"page" => params})
  end

  defp entry_var_video_id(view, index), do: input_value(view, ~s(input[name="page[vars][#{index}][video_id]"]))

  defp open(%{conn: conn, page: page}) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    await_selector(view, "[data-block-uid]")
    view
  end

  # The block is someone else's: the upload is the editor's
  defp page_with_video_ref_and_var(user) do
    author = Factory.insert(:random_user)

    module =
      ProposalFixtures.module!(author, "Film", ~s(<div>{% ref refs.clip %}{{ film }}</div>),
        refs: [ProposalFixtures.ref("clip", %{type: "video", data: %{}})],
        vars: [
          %{type: "video", key: "film", label: "Film"},
          %{type: "video", key: "backdrop", label: "Backdrop", placement: "config"}
        ]
      )

    page = Factory.insert(:page, creator: user, title: "Films", uri: "films")
    ref_uid = Brando.Utils.generate_uid()
    block_uid = Brando.Utils.generate_uid()

    block =
      %Block{}
      |> Block.recursive_block_changeset(
        %{
          "uid" => block_uid,
          "type" => "module",
          "module_id" => module.id,
          "sequence" => 0,
          "creator_id" => author.id,
          "source" => to_string(Page.Blocks),
          "refs" => [
            %{"uid" => ref_uid, "name" => "clip", "sequence" => 0, "data" => %{"type" => "video", "data" => %{}}}
          ],
          "vars" => [
            %{"type" => "video", "key" => "film", "label" => "Film", "sequence" => 0},
            %{"type" => "video", "key" => "backdrop", "label" => "Backdrop", "placement" => "config", "sequence" => 1}
          ]
        },
        author
      )
      |> Repo.insert!()

    Repo.insert!(struct(Page.Blocks, %{entry_id: page.id, block_id: block.id, sequence: 0}))
    %{page: page, ref_uid: ref_uid, block_uid: block_uid, user: user}
  end
end
