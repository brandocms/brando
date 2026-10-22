defmodule BrandoAdmin.VideoPickerUploadTest do
  @moduledoc """
  A video uploaded in the picker is handed to the field that opened it with
  `send_update(field, %{event: "select_video", id: id})`, once it is stored:
  after a provider upload (`video_upload_complete`, pushed by the provider's
  upload hook) and after a server upload (`upload_complete`, delivered by the
  upload manager). The video field had no clause for it, so the message fell
  through to its general `update/2`, which raised KeyError on `:field` and took
  the entry form down, the upload unselected.
  """
  use Brando.LiveCase

  alias Brando.Repo
  alias Brando.SyncTest
  alias Brando.SyncTest.ArticleItem
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias BrandoAdmin.Components.VideoPicker

  @form "#article_form_form"
  @row_clip ~s(input[name="article[items][0][clip_id]"])

  setup %{current_user: user} do
    {:ok, article} =
      SyncTest.create_article(
        %{title: "Article", slug: "article", language: "en", status: "published", items: [%{label: "Row"}]},
        user
      )

    [item] = Repo.preload(article, :items).items
    {:ok, article: article, item: item}
  end

  test "a video uploaded to a provider from a field's picker is set on the field", ctx do
    view = open_picker_for_clip(ctx)
    video = provider_video(ctx.current_user)

    # What the provider's upload hook pushes to the picker once the file is up
    view
    |> with_target(cid_of(view, "#video-picker"))
    |> render_hook("video_upload_complete", %{"video_id" => to_string(video.id)})

    assert Process.alive?(view.pid)
    assert clip_id(view) == to_string(video.id)

    save(view)
    assert Repo.get!(ArticleItem, ctx.item.id).clip_id == video.id
  end

  test "a video uploaded to the server from a field's picker is set on the field", ctx do
    view = open_picker_for_clip(ctx)
    video = Factory.insert(:upload_video, creator: ctx.current_user)

    # What the upload manager delivers to the picker (`deliver_asset/3`)
    Phoenix.LiveView.send_update(view.pid, VideoPicker, id: "video-picker", event: "upload_complete", asset: video)
    # Picker, then field, then form: each hands on with a message of its own
    for _ <- 1..3, do: render(view)

    assert Process.alive?(view.pid)
    assert clip_id(view) == to_string(video.id)
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
               RenderVar.update_many([{%{event: "select_video", id: video.id}, socket}])

      assert video_id == video.id
      assert_received {:var_changed, %{event: "update_block_var", data: %{video_id: ^video_id}}}
    end

    test "a gallery var adds the uploaded video, once", %{socket: socket} do
      video = Factory.insert(:video)
      socket = Phoenix.Component.assign(socket, :type, :gallery)

      [socket] = RenderVar.update_many([{%{event: "select_video", id: video.id}, socket}])
      assert [%{video_id: video_id}] = socket.assigns.gallery.gallery_objects
      assert video_id == video.id

      # Handed over again, from a URL or a provider's library: not added twice
      [socket] = RenderVar.update_many([{%{event: "video_created_from_url", video_data: %{id: video.id}}, socket}])
      assert [%{video_id: ^video_id}] = socket.assigns.gallery.gallery_objects
      refute socket.assigns[:video]
    end
  end

  defp open_picker_for_clip(%{conn: conn, article: article}) do
    {view, _html} = live_form(conn, "/admin/articles/update/#{article.id}", "article_form")

    # The row's video field opening the picker: its "Select video"
    view |> with_target(cid_of(view, @row_clip)) |> render_click("browse_video", %{})
    view
  end

  defp provider_video(user) do
    Factory.insert(:video,
      type: :bunny,
      status: :processing,
      remote_id: "6f2c1a3e-1111-2222-3333-444455556666",
      meta: %{"provider" => "bunny", "bunny" => %{"video_guid" => "6f2c1a3e-1111-2222-3333-444455556666"}},
      config_target: "video:Brando.SyncTest.ArticleItem:clip",
      creator: user
    )
  end

  defp clip_id(view) do
    view |> render() |> Floki.parse_document!() |> Floki.attribute(@row_clip, "value") |> List.first()
  end

  defp save(view) do
    view |> form(@form) |> render_submit()
    assert_push_event(view, "b:submit", %{}, 2_000)
    view |> form(@form) |> render_submit()
    assert_redirect(view, 3_000)
  end
end
