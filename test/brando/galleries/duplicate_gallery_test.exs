defmodule Brando.Galleries.DuplicateGalleryTest do
  @moduledoc """
  A gallery is owned by whatever points at it, so duplicating that owner must
  duplicate the gallery — otherwise the copy and the original share one row and
  editing either one edits both.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Galleries

  setup do
    user = Factory.insert(:random_user)
    {:ok, %{user: user}}
  end

  defp insert_gallery(user, media) do
    gallery = Factory.insert(:gallery, config_target: "ref:gallery")

    objects =
      media
      |> Enum.with_index()
      |> Enum.map(fn {{key, id, config}, index} ->
        Factory.insert(
          :gallery_object,
          Map.merge(
            %{gallery_id: gallery.id, sequence: index, creator_id: user.id, config: config},
            %{key => id}
          )
        )
      end)

    {gallery, objects}
  end

  describe "duplicate_gallery/2" do
    test "creates a new gallery row pointing at the same media", %{user: user} do
      image_one = Factory.insert(:image)
      image_two = Factory.insert(:image)
      video = Factory.insert(:video)

      {gallery, _objects} =
        insert_gallery(user, [
          {:image_id, image_one.id, %{}},
          {:image_id, image_two.id, %{"caption" => "kept"}},
          {:video_id, video.id, %{}}
        ])

      assert {:ok, copy} = Galleries.duplicate_gallery(gallery.id, user.id)

      refute copy.id == gallery.id
      assert copy.config_target == "ref:gallery"

      assert Enum.map(copy.gallery_objects, & &1.image_id) == [image_one.id, image_two.id, nil]
      assert Enum.map(copy.gallery_objects, & &1.video_id) == [nil, nil, video.id]
      assert Enum.map(copy.gallery_objects, & &1.sequence) == [0, 1, 2]

      # Per-object `config` carries the ref-level overrides (crop, caption).
      # Dropping it on a copy silently loses editing work.
      assert Enum.map(copy.gallery_objects, & &1.config) == [%{}, %{"caption" => "kept"}, %{}]
    end

    test "the copy's join rows are its own", %{user: user} do
      image = Factory.insert(:image)
      {gallery, objects} = insert_gallery(user, [{:image_id, image.id, %{}}])

      assert {:ok, copy} = Galleries.duplicate_gallery(gallery.id, user.id)

      original_object_ids = Enum.map(objects, & &1.id)
      copy_object_ids = Enum.map(copy.gallery_objects, & &1.id)

      assert copy_object_ids != original_object_ids
      assert Enum.all?(copy.gallery_objects, &(&1.gallery_id == copy.id))
    end

    test "leaves the original gallery untouched", %{user: user} do
      image = Factory.insert(:image)
      {gallery, _objects} = insert_gallery(user, [{:image_id, image.id, %{}}])

      assert {:ok, _copy} = Galleries.duplicate_gallery(gallery.id, user.id)

      {:ok, reloaded} =
        Galleries.get_gallery(%{matches: %{id: gallery.id}, preload: [:gallery_objects]})

      assert length(reloaded.gallery_objects) == 1
      assert hd(reloaded.gallery_objects).image_id == image.id
    end

    test "handles an empty gallery", %{user: user} do
      {gallery, _objects} = insert_gallery(user, [])

      assert {:ok, copy} = Galleries.duplicate_gallery(gallery.id, user.id)
      refute copy.id == gallery.id
      assert copy.gallery_objects == []
    end

    test "returns an error for a gallery that no longer exists", %{user: user} do
      assert {:error, {:gallery, :not_found}} = Galleries.duplicate_gallery(123_456_789, user.id)
    end
  end
end
