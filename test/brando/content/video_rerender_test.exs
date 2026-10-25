defmodule Brando.Content.VideoRerenderTest do
  # Saved entries serve their blocks' stored HTML. A change to a video they
  # show (its quality, what Bunny has of it, its title) renders them again.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Block
  alias Brando.Content.Blocks
  alias Brando.Factory
  alias Brando.Pages.Page
  alias Brando.ProposalFixtures

  setup do
    put_test_env(Brando.Videos.Uploaders.Bunny, cdn_hostname: "vz-1.b-cdn.net")
    user = Factory.insert(:random_user)

    video =
      Factory.insert(:video,
        creator: user,
        type: :bunny,
        status: :ready,
        meta: %{"bunny" => %{"video_guid" => "g-1", "has_mp4_fallback" => true, "available_resolutions" => "360p,720p"}}
      )

    {:ok, user: user, video: video}
  end

  defp block_with_ref(user, ref) do
    module =
      ProposalFixtures.module!(user, "Film #{System.unique_integer([:positive])}", ~s(<div>{% ref refs.clip %}</div>),
        refs: [ProposalFixtures.ref("clip", %{type: "video", data: %{}})]
      )

    %Block{}
    |> Block.recursive_block_changeset(
      %{
        "uid" => Brando.Utils.generate_uid(),
        "type" => "module",
        "module_id" => module.id,
        "sequence" => 0,
        "creator_id" => user.id,
        "source" => to_string(Page.Blocks),
        "refs" => [Map.merge(%{"uid" => Brando.Utils.generate_uid(), "name" => "clip", "sequence" => 0}, ref)]
      },
      user
    )
    |> Repo.insert!()
  end

  test "a saved page showing the video in a ref renders it again when the video changes", ctx do
    page = Factory.insert(:page, creator: ctx.user, uri: "film-#{System.unique_integer([:positive])}")

    block =
      block_with_ref(ctx.user, %{"video_id" => ctx.video.id, "data" => %{"type" => "video", "data" => %{}}})

    Repo.insert!(struct(Page.Blocks, %{entry_id: page.id, block_id: block.id, sequence: 0}))
    {:ok, page} = Blocks.render_entry(Page, page.id)
    assert page.rendered_blocks =~ "/play_720p.mp4"

    {:ok, _video} = Brando.Videos.update_video(ctx.video, %{quality: :hls}, ctx.user)

    assert Repo.reload!(page).rendered_blocks =~ "/playlist.m3u8"
  end

  test "blocks show a video through a ref, a var, or a gallery in a ref", ctx do
    in_ref = block_with_ref(ctx.user, %{"video_id" => ctx.video.id, "data" => %{"type" => "video", "data" => %{}}})

    gallery = Factory.insert(:gallery)
    Factory.insert(:gallery_object, gallery: gallery, gallery_id: gallery.id, video: ctx.video, video_id: ctx.video.id)

    in_gallery =
      block_with_ref(ctx.user, %{"gallery_id" => gallery.id, "data" => %{"type" => "gallery", "data" => %{}}})

    in_var = block_with_ref(ctx.user, %{"data" => %{"type" => "video", "data" => %{}}})

    Repo.insert!(%Brando.Content.Var{
      type: :video,
      key: "film",
      label: "Film",
      block_id: in_var.id,
      video_id: ctx.video.id
    })

    elsewhere = block_with_ref(ctx.user, %{"data" => %{"type" => "video", "data" => %{}}})

    ids = Blocks.list_block_ids_using_video(ctx.video.id)
    assert Enum.sort(ids) == Enum.sort([in_ref.id, in_gallery.id, in_var.id])
    refute elsewhere.id in ids
  end
end
