defmodule BrandoAdmin.RowProviderVideoTest do
  # A provider (here Bunny) upload from a subform row's video drawer
  # completes through the form's own handler, not the upload manager, and
  # goes to the row it was started in after the rows are reordered (#3899).
  # Synchronous: the video upload strategy and the provider's settings are
  # the application's, which every test running beside it would read.
  use Brando.LiveCase, async: false

  alias Brando.SyncTest

  @form "#article_form_form"
  @row_clip ~s(input[name="article[items][0][clip_id]"])

  setup %{current_user: user} do
    put_test_env(:default_video_upload_strategy, :bunny)

    put_test_env(Brando.Videos.Uploaders.Bunny,
      api_key: "key",
      library_id: "77",
      req_options: [plug: {Req.Test, __MODULE__}]
    )

    Req.Test.stub(__MODULE__, fn conn ->
      Req.Test.json(conn, %{"guid" => "6f2c1a3e-1111-2222-3333-444455556666", "videoLibraryId" => 77})
    end)

    {:ok, article} =
      SyncTest.create_article(
        %{
          title: "Example Hotel",
          slug: "example-hotel",
          language: "en",
          status: "published",
          items: [%{label: "A"}, %{label: "B"}, %{label: "C"}]
        },
        user
      )

    %{article: article}
  end

  test "a provider video from a row's drawer goes to its row after the rows are reordered", ctx do
    {view, _html} = live_form(ctx.conn, "/admin/articles/update/#{ctx.article.id}", "article_form")
    view |> with_target(cid_of(view, @row_clip)) |> render_click("open_video", %{})

    render_hook(view, "get_video_upload_url", %{
      "request_ref" => "row-a",
      "filename" => "clip.mp4",
      "size" => 1_000,
      "mime_type" => "video/mp4"
    })

    assert_push_event(view, "video_upload_url_ready", %{request_ref: "row-a", video_id: video_id, upload_token: token})

    params =
      view
      |> render()
      |> form_params(@form)
      |> put_in(["article", "sort_items_ids"], ["1", "2", "0"])
      |> Map.put("_target", ["article", "sort_items_ids"])

    view |> element(@form) |> render_change(params)
    assert row_inputs(render(view), "label") == ["B", "C", "A"]

    render_hook(view, "video_upload_complete", %{"request_ref" => "row-a", "upload_token" => token})

    assert row_inputs(render(view), "clip_id") == ["", "", to_string(video_id)]
  end

  defp row_inputs(html, field) do
    html
    |> Floki.parse_document!()
    |> Floki.find(~s(#{@form} input[name^="article[items]"][name$="[#{field}]"]))
    |> Floki.attribute("value")
  end
end
