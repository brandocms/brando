defmodule BrandoAdmin.VideoPickerUploadTest do
  @moduledoc """
  A video uploaded in the picker is handed to the field it was uploaded for
  with `send_update(field, %{event: "select_video", id: id, ...})`, once it
  is stored: after a provider upload (`video_upload_complete`, pushed by the
  provider's upload hook) and after a server upload (`upload_complete`,
  delivered by the upload manager).

  The editor may close the picker and open it for another field while the
  file transfers. The upload still goes to the field it was started for, and
  only if that field shows what it showed then; otherwise it stays in the
  library. Before, it went to whichever field had opened the picker last.
  """
  use Brando.LiveCase

  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.ArticleItem
  alias Brando.Videos.Uploaders.Bunny
  alias BrandoAdmin.Components.Assets.ProviderVideoUpload
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias BrandoAdmin.Components.VideoPicker

  @form "#article_form_form"
  @clip_a ~s(input[name="article[items][0][clip_id]"])
  @clip_b ~s(input[name="article[items][1][clip_id]"])
  @guid "6f2c1a3e-1111-2222-3333-444455556666"

  setup %{current_user: user} do
    {:ok, article} =
      SyncTest.create_article(
        %{
          title: "Article",
          slug: "article",
          language: "en",
          status: "published",
          items: [%{label: "Row A", sequence: 0}, %{label: "Row B", sequence: 1}]
        },
        user
      )

    items = article |> Repo.preload(:items) |> Map.fetch!(:items) |> Enum.sort_by(& &1.sequence)
    {:ok, article: article, items: items}
  end

  describe "a provider upload" do
    setup do
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

      :ok
    end

    test "is set on the field it was started for", ctx do
      view = open(ctx)

      browse(view, @clip_a)
      {video_id, token} = start_provider_upload(view, "picker-1")

      complete_provider_upload(view, "picker-1", token)
      assert clip_id(view, @clip_a) == to_string(video_id)

      save(view)
      assert [a, b] = saved_clip_ids(ctx)
      assert a == video_id
      assert b == nil
    end

    test "goes to the field it was started for, not to the one that opened the picker since", ctx do
      view = open(ctx)

      browse(view, @clip_a)
      {video_id, token} = start_provider_upload(view, "picker-2")
      browse(view, @clip_b)
      complete_provider_upload(view, "picker-2", token)

      assert Process.alive?(view.pid)
      assert clip_id(view, @clip_a) == to_string(video_id)
      assert clip_id(view, @clip_b) == ""
    end

    # The hook sends one file at a time: a file picked for A, queued behind
    # another upload, asks for its destination once the picker is open for B.
    test "queued goes to the field it was picked for", ctx do
      view = open(ctx)

      browse(view, @clip_a)
      origin = provider_upload_origin(view)
      assert origin["expected_asset_id"] == "none"
      browse(view, @clip_b)
      {video_id, token} = start_provider_upload(view, "picker-queued", origin)
      complete_provider_upload(view, "picker-queued", token)

      assert clip_id(view, @clip_a) == to_string(video_id)
      assert clip_id(view, @clip_b) == ""
    end

    test "stays in the library when its field shows another video by then", ctx do
      picked = Factory.insert(:video)
      view = open(ctx)

      browse(view, @clip_a)
      {video_id, token} = start_provider_upload(view, "picker-3")
      view |> with_target(cid_of(view, @clip_a)) |> render_hook("select_video", %{"id" => picked.id})
      browse(view, @clip_b)
      complete_provider_upload(view, "picker-3", token)

      assert clip_id(view, @clip_a) == to_string(picked.id)
      assert clip_id(view, @clip_b) == ""
      assert Repo.get(Brando.Videos.Video, video_id)
    end

    # Cloudflare records that the file arrived. The video's provider state is
    # the system's to write, so an upload its creator started still moves on
    # when they were demoted since; an upload nobody waits for leaves the
    # fields alone, and the form keeps running.
    test "from a creator demoted since is finished all the same, and the form keeps running", ctx do
      view = open(ctx)
      browse(view, @clip_a)

      video =
        Factory.insert(:video,
          type: :cloudflare,
          status: :uploading,
          remote_id: "cf-uid",
          meta: %{"provider" => "cloudflare"},
          creator: ctx.current_user
        )

      token = ProviderVideoUpload.upload_token(video, ctx.current_user, "gone")
      ctx.current_user |> Ecto.Changeset.change(role: :user) |> Repo.update!()

      complete_provider_upload(view, "gone", token)

      assert Process.alive?(view.pid)
      assert Repo.get!(Brando.Videos.Video, video.id).status == :processing
      assert clip_id(view, @clip_a) == ""
    end

    # The browser says which upload finished with the token it was given for
    # it, not with a video id: an id of its own choosing used to move any
    # video out of uploading and onto the field.
    test "completes only an upload this user started, for that request", ctx do
      view = open(ctx)
      browse(view, @clip_a)
      {video_id, token} = start_provider_upload(view, "picker-own")

      other_user = Factory.insert(:random_user)

      others =
        Factory.insert(:video,
          type: :cloudflare,
          status: :uploading,
          remote_id: "cf-other",
          meta: %{"provider" => "cloudflare"},
          creator: other_user
        )

      # A video id alone, someone else's upload, a token for another request
      # or another user, and a forged token are all refused.
      view |> picker() |> render_hook("video_upload_complete", %{"request_ref" => "x", "video_id" => others.id})
      complete_provider_upload(view, "x", ProviderVideoUpload.upload_token(others, other_user, "x"))
      complete_provider_upload(view, "x", ProviderVideoUpload.upload_token(others, ctx.current_user, "x"))
      complete_provider_upload(view, "picker-other-ref", token)
      complete_provider_upload(view, "picker-own", token <> "x")

      assert Repo.get!(Brando.Videos.Video, others.id).status == :uploading
      assert clip_id(view, @clip_a) == ""

      complete_provider_upload(view, "picker-own", token)
      assert clip_id(view, @clip_a) == to_string(video_id)
    end
  end

  describe "a server upload" do
    setup do
      put_test_env(:default_video_upload_strategy, :local)
      :ok
    end

    test "goes to the field it was started for, not to the one that opened the picker since", ctx do
      view = open(ctx)

      browse(view, @clip_a)
      {ref, expected} = server_upload_target(view)
      assert expected == "none"

      browse(view, @clip_b)
      deliver_server_upload(view, Factory.insert(:upload_video, creator: ctx.current_user), ref, expected)

      assert Process.alive?(view.pid)
      video_id = clip_id(view, @clip_a)
      assert video_id != ""
      assert clip_id(view, @clip_b) == ""
    end

    test "stays in the library when its field shows another video by then", ctx do
      picked = Factory.insert(:video)
      view = open(ctx)

      browse(view, @clip_a)
      {ref, expected} = server_upload_target(view)
      view |> with_target(cid_of(view, @clip_a)) |> render_hook("select_video", %{"id" => picked.id})
      browse(view, @clip_b)
      deliver_server_upload(view, Factory.insert(:upload_video, creator: ctx.current_user), ref, expected)

      assert clip_id(view, @clip_a) == to_string(picked.id)
      assert clip_id(view, @clip_b) == ""
    end

    test "from an opening the picker no longer knows stays in the library", ctx do
      view = open(ctx)

      browse(view, @clip_a)
      deliver_server_upload(view, Factory.insert(:upload_video, creator: ctx.current_user), "vp-0", "none")

      assert Process.alive?(view.pid)
      assert clip_id(view, @clip_a) == ""
    end
  end

  describe "a block var" do
    setup %{current_user: user} do
      test_pid = self()

      socket =
        %Phoenix.LiveView.Socket{}
        |> Phoenix.Component.assign(
          id: "var-clip",
          key: "clip",
          gallery: nil,
          video_id: nil,
          current_user_id: user.id,
          on_change: &send(test_pid, {:var_changed, &1})
        )

      {:ok, socket: socket}
    end

    test "a video var takes the uploaded video", %{socket: socket} do
      video = Factory.insert(:video)
      socket = Phoenix.Component.assign(socket, :type, :video)

      # `id` here is the video's: the result is still this component's
      assert [%{assigns: %{id: "var-clip", video_id: video_id}}] =
               RenderVar.update_many([
                 {%{event: "select_video", id: video.id, expected_asset_id: "none", pick_context: "clip"}, socket}
               ])

      assert video_id == video.id
      assert_received {:var_changed, %{event: "update_block_var", data: %{video_id: ^video_id}}}
    end

    test "a video var that shows another video, or another var, keeps it", %{socket: socket} do
      video = Factory.insert(:video)
      picked = Factory.insert(:video)
      socket = Phoenix.Component.assign(socket, type: :video, video_id: picked.id)

      assert [%{assigns: %{video_id: video_id}}] =
               RenderVar.update_many([{%{event: "select_video", id: video.id, expected_asset_id: "none"}, socket}])

      assert video_id == picked.id

      socket = Phoenix.Component.assign(socket, video_id: nil)

      assert [%{assigns: %{video_id: nil}}] =
               RenderVar.update_many([
                 {%{event: "select_video", id: video.id, expected_asset_id: "none", pick_context: "other"}, socket}
               ])

      refute_received {:var_changed, _}
    end

    test "a gallery var adds the uploaded video, once", %{socket: socket} do
      video = Factory.insert(:video)
      socket = Phoenix.Component.assign(socket, :type, :gallery)

      [socket] = RenderVar.update_many([{%{event: "select_video", id: video.id}, socket}])
      assert [%{video_id: video_id}] = socket.assigns.gallery.gallery_objects
      assert video_id == video.id
      # The pickers, which may be open for another target, are left alone
      refute_received {:phoenix, :send_update, {{VideoPicker, "video-picker"}, _}}
      refute_received {:phoenix, :send_update, {{BrandoAdmin.Components.ImagePicker, "image-picker"}, _}}

      # Handed over again, from a URL or a provider's library: not added twice
      [socket] = RenderVar.update_many([{%{event: "video_created_from_url", video_data: %{id: video.id}}, socket}])
      assert [%{video_id: ^video_id}] = socket.assigns.gallery.gallery_objects
      refute socket.assigns[:video]
    end
  end

  defp open(%{conn: conn, article: article}) do
    {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}", "article_form")
    view
  end

  # The row's video field opening the picker: its "Select video"
  defp browse(view, field) do
    view |> with_target(cid_of(view, field)) |> render_click("browse_video", %{})
    render(view)
  end

  defp picker(view), do: with_target(view, cid_of(view, "#video-picker"))

  # What the provider's upload hook in the picker pushes before the transfer
  defp start_provider_upload(view, request_ref, origin \\ %{}) do
    view
    |> picker()
    |> render_hook(
      "get_video_upload_url",
      Map.merge(origin, %{
        "request_ref" => request_ref,
        "filename" => "clip.mp4",
        "size" => 1_000,
        "mime_type" => "video/mp4"
      })
    )

    assert_push_event(view, "video_upload_url_ready", %{
      request_ref: ^request_ref,
      video_id: video_id,
      upload_token: token
    })

    {video_id, token}
  end

  # ... and once the file is up, with the token the server signed for it
  defp complete_provider_upload(view, request_ref, token) do
    view |> picker() |> render_hook("video_upload_complete", %{"request_ref" => request_ref, "upload_token" => token})
    # Picker, then field, then form: each hands on with a message of its own
    for _ <- 1..3, do: render(view)
  end

  # What the picker's server upload trigger puts in the upload's target
  defp server_upload_target(view) do
    attribute = picker_attribute(view, "#video-uploader-video-picker")
    {attribute.("data-ref"), attribute.("data-expected-asset-id")}
  end

  # What the provider's hook in the picker sends with a file picked now
  defp provider_upload_origin(view) do
    attribute = picker_attribute(view, "#video-provider-uploader-video-picker")
    %{"opening" => attribute.("data-ref"), "expected_asset_id" => attribute.("data-expected-asset-id")}
  end

  defp picker_attribute(view, selector) do
    [element] = view |> render() |> Floki.parse_document!() |> Floki.find(selector)
    &(element |> Floki.attribute(&1) |> List.first())
  end

  # What the upload manager delivers to the picker (`deliver_asset/3`)
  defp deliver_server_upload(view, video, ref, expected) do
    Phoenix.LiveView.send_update(view.pid, VideoPicker,
      id: "video-picker",
      event: "upload_complete",
      asset: video,
      ref: ref,
      expected_asset_id: expected
    )

    for _ <- 1..3, do: render(view)
  end

  defp clip_id(view, field) do
    view |> render() |> Floki.parse_document!() |> Floki.attribute(field, "value") |> List.first()
  end

  defp saved_clip_ids(%{items: items}), do: Enum.map(items, &Repo.get!(ArticleItem, &1.id).clip_id)

  defp save(view) do
    view |> form(@form) |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form(@form) |> render_submit()
    assert_redirect(view, 3_000)
  end
end
