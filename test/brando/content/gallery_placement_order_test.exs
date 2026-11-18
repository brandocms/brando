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
end
