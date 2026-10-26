defmodule BrandoAdmin.VideoFieldProviderUploadTest do
  @moduledoc """
  A video field whose config uploads to a provider (Mux, Bunny, Cloudflare,
  Vimeo) takes an upload itself, as the video picker does: Upload and a drop
  hand the file to the provider's hook rendered in the field, which asks the
  field for each upload's destination and moves the bytes straight to the
  provider. Before, the field offered no Upload and refused a drop with "Use
  Select video to upload a video with this provider".
  """
  use Brando.LiveCase

  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.ArticleItem
  alias Brando.Videos.Uploaders.Bunny

  @row_clip ~s(input[name="article[items][0][clip_id]"])
  @row_media "#article_items_0_clip-media"
  @hook "#article_items_0_clip-video-uploader"
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

    {:ok, article} =
      SyncTest.create_article(
        %{title: "Article", slug: "article", language: "en", status: "published", items: [%{label: "Row"}]},
        user
      )

    [item] = Repo.preload(article, :items).items
    {:ok, article: article, item: item}
  end

  test "the field offers Upload, through the provider's hook", ctx do
    view = open(ctx)

    assert has_element?(view, ~s(#{@row_media}[data-upload-enabled="true"][data-video-hook-id]))
    assert has_element?(view, "#{@row_media} .upload-trigger")
    assert has_element?(view, ~s(#{@hook}[phx-hook="Brando.BunnyUploader"]))
  end

  test "an upload is created with the field's config and set on the field once it is up", ctx do
    view = open(ctx)

    view
    |> with_target(cid_of(view, @hook))
    |> render_hook("get_video_upload_url", %{
      "request_ref" => "field-1",
      "filename" => "clip.mp4",
      "size" => 1_000,
      "mime_type" => "video/mp4"
    })

    assert_push_event(view, "video_upload_url_ready", %{
      request_ref: "field-1",
      video_id: video_id,
      upload_token: token,
      tus_auth: tus_auth
    })

    assert tus_auth.video_id == @guid

    video = Repo.get!(Brando.Videos.Video, video_id)
    assert video.type == :bunny
    assert video.config_target == "video:Brando.SyncTest.ArticleItem:clip"

    # Not the field's until the file is with the provider
    assert clip_id(view) == ""

    view
    |> with_target(cid_of(view, @hook))
    |> render_hook("video_upload_complete", %{"request_ref" => "field-1", "upload_token" => token})

    assert clip_id(view) == to_string(video_id)

    save(view)
    assert Repo.get!(ArticleItem, ctx.item.id).clip_id == video_id
  end

  test "an upload that finishes after another video was picked leaves the pick", ctx do
    picked = Factory.insert(:video)
    view = open(ctx)

    view
    |> with_target(cid_of(view, @hook))
    |> render_hook("get_video_upload_url", %{
      "request_ref" => "field-late",
      "filename" => "clip.mp4",
      "size" => 1_000,
      "mime_type" => "video/mp4"
    })

    assert_push_event(view, "video_upload_url_ready", %{
      request_ref: "field-late",
      video_id: video_id,
      upload_token: token
    })

    view |> with_target(cid_of(view, @hook)) |> render_hook("select_video", %{"id" => picked.id})
    assert clip_id(view) == to_string(picked.id)

    view
    |> with_target(cid_of(view, @hook))
    |> render_hook("video_upload_complete", %{"request_ref" => "field-late", "upload_token" => token})

    assert clip_id(view) == to_string(picked.id)
    # The upload stays in the library
    assert Repo.get(Brando.Videos.Video, video_id)
  end

  test "a refused upload is reported to the hook", ctx do
    view = open(ctx)

    view
    |> with_target(cid_of(view, @hook))
    |> render_hook("get_video_upload_url", %{
      "request_ref" => "field-2",
      "filename" => "notes.txt",
      "size" => 1_000,
      "mime_type" => "text/plain"
    })

    assert_push_event(view, "video_upload_url_error", %{request_ref: "field-2", error: error})
    assert is_binary(error)
    assert Process.alive?(view.pid)
  end

  test "a provider that refuses is reported in words, not its raw answer", ctx do
    Req.Test.stub(Bunny, fn conn ->
      conn
      |> Plug.Conn.put_status(401)
      |> Req.Test.json(%{"Message" => "Authentication has been denied for this request.", "StatusCode" => 401})
    end)

    view = open(ctx)

    view
    |> with_target(cid_of(view, @hook))
    |> render_hook("get_video_upload_url", %{
      "request_ref" => "field-3",
      "filename" => "clip.mp4",
      "size" => 1_000,
      "mime_type" => "video/mp4"
    })

    assert_push_event(view, "video_upload_url_error", %{request_ref: "field-3", error: error})
    assert error == "The video provider refused the upload. Check its settings, or try again."
  end

  test "without the provider's credentials the field cannot upload", ctx do
    put_test_env(Bunny, [])
    view = open(ctx)

    assert has_element?(view, ~s(#{@row_media}[data-upload-enabled="false"]))
    refute has_element?(view, @hook)
  end

  defp open(%{conn: conn, article: article}) do
    {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}", "article_form")
    view
  end

  defp clip_id(view) do
    view |> render() |> Floki.parse_document!() |> Floki.attribute(@row_clip, "value") |> List.first()
  end

  defp save(view) do
    view |> form("#article_form_form") |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form("#article_form_form") |> render_submit()
    assert_redirect(view, 3_000)
  end
end
