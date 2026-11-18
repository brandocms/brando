defmodule Brando.Content.GalleryPlacementOrderTest do
  # A gallery block's caption overrides name a repeated image's placement by
  # its position among that image's placements. Reordering or removing gallery
  # objects in the form moves each caption with its object.
  use Brando.ConnCase, async: true

  alias Brando.Content.Block
  alias Brando.Factory
  alias Brando.Villain.Blocks.GalleryObjectOverride

  setup do
    user = Factory.insert(:random_user)
    repeated = Factory.insert(:image, creator: user)
    other = Factory.insert(:image, creator: user)
    gallery = Factory.insert(:gallery)

    objects =
      for {image, sequence} <- Enum.with_index([repeated, other, repeated]) do
        Factory.insert(:gallery_object, gallery_id: gallery.id, image_id: image.id, sequence: sequence)
      end

    gallery = Brando.Repo.preload(gallery, :gallery_objects, force: true)

    ref = %Brando.Content.Ref{
      uid: "galleryref",
      name: "gallery",
      gallery_id: gallery.id,
      gallery: gallery,
      data: %Brando.Villain.Blocks.GalleryBlock{type: "gallery", data: %Brando.Villain.Blocks.GalleryBlock.Data{}}
    }

    {:ok, user: user, ref: ref, gallery: gallery, objects: objects, repeated: repeated, other: other}
  end

  # The params the gallery block's form submits: objects and overrides named by
  # their index in the form as rendered, the objects' order in the sort param.
  defp params(ctx, overrides, sort, drop \\ []) do
    objects =
      ctx.objects
      |> Enum.with_index()
      |> Map.new(fn {object, index} ->
        {to_string(index), %{"id" => to_string(object.id), "image_id" => to_string(object.image_id), "video_id" => ""}}
      end)

    %{
      "gallery" => %{
        "id" => to_string(ctx.gallery.id),
        "gallery_objects" => objects,
        "sort_gallery_object_ids" => Enum.map(sort, &to_string/1),
        "drop_gallery_object_ids" => [""] ++ Enum.map(drop, &to_string/1)
      },
      "data" => %{
        "type" => "gallery",
        "data" => %{
          "gallery_object_overrides" =>
            overrides
            |> Enum.with_index()
            |> Map.new(fn {{image, placement, title}, index} ->
              {to_string(index),
               %{
                 "object_id" => to_string(image.id),
                 "object_type" => "image",
                 "placement" => to_string(placement),
                 "title" => title
               }}
            end)
        }
      }
    }
  end

  defp captions(changeset) do
    ref = Ecto.Changeset.apply_changes(changeset)

    ref.data.data.gallery_object_overrides
    |> Enum.map(&{&1.object_id, GalleryObjectOverride.placement(&1), &1.title})
    |> Enum.sort()
  end

  defp gallery_images(changeset) do
    ref = Ecto.Changeset.apply_changes(changeset)
    Enum.map(ref.gallery.gallery_objects, & &1.image_id)
  end

  test "a caption moves with its placement when the gallery is reordered", ctx do
    overrides = [{ctx.repeated, 0, "First"}, {ctx.other, "", "Other"}, {ctx.repeated, 1, "Third"}]

    changeset = Block.ref_changeset(ctx.ref, params(ctx, overrides, [2, 1, 0]), ctx.user)

    assert gallery_images(changeset) == [ctx.repeated.id, ctx.other.id, ctx.repeated.id]
    id = to_string(ctx.repeated.id)

    # The object that was third is now first, with its caption.
    assert captions(changeset) ==
             Enum.sort([{id, 0, "Third"}, {to_string(ctx.other.id), nil, "Other"}, {id, 1, "First"}])
  end

  test "an order that keeps the repeats in place leaves the placements alone", ctx do
    overrides = [{ctx.repeated, 0, "First"}, {ctx.other, "", "Other"}, {ctx.repeated, 1, "Third"}]

    changeset = Block.ref_changeset(ctx.ref, params(ctx, overrides, [1, 0, 2]), ctx.user)

    id = to_string(ctx.repeated.id)

    assert captions(changeset) ==
             Enum.sort([{id, 0, "First"}, {to_string(ctx.other.id), nil, "Other"}, {id, 1, "Third"}])
  end

  test "removing a placement removes its caption, and the image left once keeps its own", ctx do
    overrides = [{ctx.repeated, 0, "First"}, {ctx.other, "", "Other"}, {ctx.repeated, 1, "Third"}]

    changeset = Block.ref_changeset(ctx.ref, params(ctx, overrides, [0, 1, 2], [0]), ctx.user)

    assert gallery_images(changeset) == [ctx.other.id, ctx.repeated.id]
    id = to_string(ctx.repeated.id)

    assert captions(changeset) == Enum.sort([{to_string(ctx.other.id), nil, "Other"}, {id, nil, "Third"}])
  end

  describe "settle/1" do
    defp settled(objects, overrides) do
      %{"gallery" => %{"gallery_objects" => objects}, "data" => %{"data" => %{"gallery_object_overrides" => overrides}}}
      |> GalleryObjectOverride.settle()
      |> get_in(["data", "data", "gallery_object_overrides"])
    end

    # Two copies of an image not saved yet give the same uid: it names
    # neither, and neither override moves
    test "a uid that two objects give moves no override" do
      objects = [%{"image_id" => "5"}, %{"image_id" => "5"}]

      overrides = [
        %{"uid" => "image-5", "object_id" => "5", "object_type" => "image", "placement" => 0},
        %{"uid" => "image-5-2", "object_id" => "5", "object_type" => "image", "placement" => 1}
      ]

      assert settled(objects, overrides) == overrides
    end

    # An editor's change to an override another editor removed meanwhile
    # arrives as the fields it changed. A legacy override, stored without a
    # type (and without a uid), is not one of them.
    test "drops a partial override, and keeps one stored without a type" do
      objects = [%{"id" => 1, "image_id" => "5"}]
      legacy = %{"object_id" => "5", "title" => "Legacy"}

      assert settled(objects, [legacy, %{"uid" => "g9", "object_id" => "7"}, %{"uid" => "g8", "title" => "x"}]) ==
               [legacy]
    end
  end

  describe "replace_media/4" do
    defp titled(id, placement, title),
      do: %GalleryObjectOverride{object_id: id, object_type: :image, placement: placement, title: title}

    defp summary(overrides), do: overrides |> Enum.map(&{&1.object_id, &1.placement, &1.title}) |> Enum.sort()

    test "the replaced placement takes its caption, the others are renumbered" do
      keys = [{:image, "1"}, {:image, "2"}, {:image, "1"}, {:image, "1"}]
      overrides = [titled("1", 0, "A"), titled("2", nil, "Other"), titled("1", 1, "B"), titled("1", 2, "C")]

      assert overrides |> GalleryObjectOverride.replace_media(keys, 2, {:image, "9"}) |> summary() ==
               Enum.sort([{"1", 0, "A"}, {"1", 1, "C"}, {"2", nil, "Other"}, {"9", nil, "B"}])
    end

    test "an override for every placement stays with the others, and the copy gets one like it" do
      keys = [{:image, "1"}, {:image, "1"}]

      assert [titled("1", nil, "Shared")] |> GalleryObjectOverride.replace_media(keys, 0, {:image, "9"}) |> summary() ==
               [{"1", nil, "Shared"}, {"9", nil, "Shared"}]
    end

    test "a media held once takes its overrides along" do
      keys = [{:image, "1"}, {:image, "2"}]

      assert [titled("1", nil, "One"), titled("2", nil, "Two")]
             |> GalleryObjectOverride.replace_media(keys, 0, {:image, "9"})
             |> summary() == [{"2", nil, "Two"}, {"9", nil, "One"}]
    end
  end
end
