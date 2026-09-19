defmodule Brando.Villain.StaleRefAssocTest do
  @moduledoc """
  A ref's `*_id` is the source of truth for which asset it points at; the
  preloaded association is only a cache of that id.

  Live preview materializes a root block by casting the op store's params — which
  carry the freshly picked `*_id` — onto the block's *persisted* base struct,
  whose association still holds the previously saved asset. Ecto never refetches
  an already-loaded association, so a swapped-in video rendered as the old one
  and a removed one kept rendering, right up until the entry was saved and
  reloaded from the database.

  These tests pin the disagreement directly: build a ref whose FK and
  association point at different assets, and assert the FK wins.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content
  alias Brando.Factory
  alias Brando.Utils

  setup do
    user = Factory.insert(:random_user)
    {:ok, %{user: user}}
  end

  defp render_video_ref(user, ref_attrs, block_data \\ %{}) do
    module_params =
      Factory.params_for(:module, %{
        code: "Video: {% ref refs.hero_video %}",
        refs: [
          %{
            name: "hero_video",
            uid: Utils.generate_uid(),
            data: %{type: "video", data: %{}}
          }
        ]
      })

    {:ok, module} = Content.create_module(module_params, user)

    ref =
      Map.merge(
        %{
          name: "hero_video",
          description: nil,
          uid: Utils.generate_uid(),
          data: %Brando.Villain.Blocks.VideoBlock{
            type: "video",
            data: struct(Brando.Villain.Blocks.VideoBlock.Data, block_data)
          }
        },
        ref_attrs
      )

    block = %{
      block: %{type: :module, module_id: module.id, refs: [ref], uid: Utils.generate_uid(), vars: []}
    }

    Brando.Villain.parse([block], %Brando.Pages.Page{})
  end

  defp render_picture_ref(user, ref_attrs) do
    module_params =
      Factory.params_for(:module, %{
        code: "Picture: {% ref refs.hero_picture %}",
        refs: [
          %{
            name: "hero_picture",
            uid: Utils.generate_uid(),
            data: %{type: "picture", data: %{}}
          }
        ]
      })

    {:ok, module} = Content.create_module(module_params, user)

    ref =
      Map.merge(
        %{
          name: "hero_picture",
          description: nil,
          uid: Utils.generate_uid(),
          data: %Brando.Villain.Blocks.PictureBlock{
            type: "picture",
            data: %Brando.Villain.Blocks.PictureBlock.Data{}
          }
        },
        ref_attrs
      )

    block = %{
      block: %{type: :module, module_id: module.id, refs: [ref], uid: Utils.generate_uid(), vars: []}
    }

    Brando.Villain.parse([block], %Brando.Pages.Page{})
  end

  describe "a ref whose FK and preloaded association disagree" do
    # The reported bug: swap a video in a block with live preview open and the
    # preview keeps showing the old one, through a reload and a preview reopen,
    # until the entry is saved and re-read from the database.
    test "renders the video the FK points at, not the stale preload", %{user: user} do
      old = Factory.insert(:external_file_video, creator: user, source_url: "https://example.com/old-video.mp4")
      new = Factory.insert(:external_file_video, creator: user, source_url: "https://example.com/new-video.mp4")

      parsed = render_video_ref(user, %{video_id: new.id, video: old})

      assert parsed =~ "new-video.mp4"
      refute parsed =~ "old-video.mp4"
    end

    # `reset_video` sends `video_id: nil` and leaves the association untouched on
    # the persisted base struct. Without the guard the removed video rendered on.
    test "renders no video once the FK is cleared, even with the old one preloaded", %{user: user} do
      old = Factory.insert(:external_file_video, creator: user, source_url: "https://example.com/old-video.mp4")

      parsed = render_video_ref(user, %{video_id: nil, video: old})

      refute parsed =~ "old-video.mp4"
      refute parsed =~ "<video"
    end

    test "still renders the video when FK and association agree", %{user: user} do
      video = Factory.insert(:external_file_video, creator: user, source_url: "https://example.com/kept-video.mp4")

      parsed = render_video_ref(user, %{video_id: video.id, video: video})

      assert parsed =~ "kept-video.mp4"
    end

    # A freshly picked id has not been cast yet and arrives as a string. It must
    # still compare equal to the loaded association's integer id, or every pick
    # would be treated as stale and refetched on each render.
    test "treats a not-yet-cast string FK as agreeing with the association", %{user: user} do
      video = Factory.insert(:external_file_video, creator: user, source_url: "https://example.com/string-id.mp4")

      parsed = render_video_ref(user, %{video_id: to_string(video.id), video: video})

      assert parsed =~ "string-id.mp4"
    end

    # Same defect, same fix — picture refs carry a flat `image_id` too.
    test "renders the image the FK points at, not the stale preload", %{user: user} do
      old = Factory.insert(:image, creator: user, path: "image/old-image.jpg", sizes: %{})
      new = Factory.insert(:image, creator: user, path: "image/new-image.jpg", sizes: %{})

      parsed = render_picture_ref(user, %{image_id: new.id, image: old})

      assert parsed =~ "new-image.jpg"
      refute parsed =~ "old-image.jpg"
    end
  end

  describe "block-level playback overrides" do
    # Locks the server half of the autoplay contract: the record carries no
    # autoplay of its own, the block override supplies it, and both the wrapper
    # hook the frontend reads and the element attribute have to come out set.
    test "an autoplay override renders autoplay even when the record has none", %{user: user} do
      video =
        Factory.insert(:external_file_video,
          creator: user,
          source_url: "https://example.com/autoplay.mp4",
          autoplay: nil
        )

      parsed =
        render_video_ref(user, %{video_id: video.id, video: video}, %{autoplay: true, muted: true, loop: true})

      assert parsed =~ "data-autoplay"
      assert parsed =~ "autoplay"
      assert parsed =~ "muted"
    end

    # `false` is a real override, distinct from "not set" — it has to beat a
    # record that autoplays rather than reading as absent.
    test "an autoplay override of false beats a record that autoplays", %{user: user} do
      video =
        Factory.insert(:external_file_video,
          creator: user,
          source_url: "https://example.com/no-autoplay.mp4",
          autoplay: true
        )

      parsed = render_video_ref(user, %{video_id: video.id, video: video}, %{autoplay: false})

      refute parsed =~ "data-autoplay"
    end
  end
end
