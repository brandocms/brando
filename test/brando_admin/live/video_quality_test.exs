defmodule BrandoAdmin.VideoQualityTest do
  @moduledoc """
  A video ref's settings offer the video's qualities under Playback: Automatic,
  Streaming and the MP4s the video has, below the video's own setting. A video
  without renditions to choose from has no select, and keeps the ref's value
  in a hidden input.
  """
  use Brando.LiveCase

  alias Brando.Content.Block
  alias Brando.Pages.Page
  alias Brando.ProposalFixtures

  setup do
    put_test_env(Brando.Videos.Uploaders.Bunny, cdn_hostname: "vz-1.b-cdn.net")
    :ok
  end

  defp bunny(user, attrs) do
    Factory.insert(
      :video,
      Keyword.merge(
        [
          creator: user,
          type: :bunny,
          status: :ready,
          meta: %{"bunny" => %{"video_guid" => "g-1", "has_mp4_fallback" => true, "available_resolutions" => "360p,720p"}}
        ],
        attrs
      )
    )
  end

  defp open_ref_config(%{conn: conn}, page, ref_uid) do
    {view, _html} = live_form(conn, "/admin/pages/update/#{page.id}")
    await_selector(view, "[data-block-uid]")

    view
    |> element(~s([phx-click="open_block_config"][phx-value-uid="#{ref_uid}"]))
    |> render_click()

    view
  end

  defp options(view) do
    view
    |> render()
    |> Floki.parse_document!()
    |> Floki.find(~s(select[name$="[refs][0][data][data][quality]"] option))
    |> Enum.map(&{Floki.attribute(&1, "value") |> List.first(), Floki.text(&1) |> String.trim()})
  end

  test "a Bunny video's ref offers its qualities, under the video's own", %{current_user: user} = ctx do
    video = bunny(user, quality: :mp4_720)
    {page, ref_uid} = page_with_video_ref(user, video, %{"quality" => "hls"})
    view = open_ref_config(ctx, page, ref_uid)

    assert options(view) == [
             {"", "Video’s setting (MP4, 720p)"},
             {"auto", "Automatic"},
             {"hls", "Streaming (HLS)"},
             {"mp4_360", "MP4, 360p"},
             {"mp4_720", "MP4, 720p"}
           ]

    assert has_element?(view, ~s(select[name$="[refs][0][data][data][quality]"] option[value="hls"][selected]))
  end

  test "a video without renditions keeps the ref's quality in a hidden input", %{current_user: user} = ctx do
    video = Factory.insert(:upload_video, creator: user)
    {page, ref_uid} = page_with_video_ref(user, video, %{"quality" => "hls"})
    view = open_ref_config(ctx, page, ref_uid)

    assert options(view) == []
    assert has_element?(view, ~s(input[type="hidden"][name$="[refs][0][data][data][quality]"][value="hls"]))
  end

  defp page_with_video_ref(user, video, ref_data) do
    module =
      ProposalFixtures.module!(user, "Film", ~s(<div>{% ref refs.clip %}</div>),
        refs: [ProposalFixtures.ref("clip", %{type: "video", data: %{}})]
      )

    page = Factory.insert(:page, creator: user, title: "Films", uri: "films-#{System.unique_integer([:positive])}")
    ref_uid = Brando.Utils.generate_uid()

    block =
      %Block{}
      |> Block.recursive_block_changeset(
        %{
          "uid" => Brando.Utils.generate_uid(),
          "type" => "module",
          "module_id" => module.id,
          "sequence" => 0,
          "creator_id" => user.id,
          "source" => to_string(Page.Blocks),
          "refs" => [
            %{
              "uid" => ref_uid,
              "name" => "clip",
              "sequence" => 0,
              "video_id" => video.id,
              "data" => %{"type" => "video", "data" => ref_data}
            }
          ]
        },
        user
      )
      |> Repo.insert!()

    Repo.insert!(struct(Page.Blocks, %{entry_id: page.id, block_id: block.id, sequence: 0}))
    {page, ref_uid}
  end
end
