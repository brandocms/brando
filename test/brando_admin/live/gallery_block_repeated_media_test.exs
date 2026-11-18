defmodule BrandoAdmin.GalleryBlockRepeatedMediaTest do
  # A gallery may hold one image more than once (imported content, a script
  # reusing one upload). Each placement is its own gallery object, with its own
  # caption, and the entry form opens with it (#3617).
  use Brando.LiveCase, async: true

  alias Brando.Content.Ref
  alias Brando.Villain.Blocks.GalleryObjectOverride

  setup %{current_user: user} do
    {:ok, module} =
      Brando.Content.create_module(
        Factory.params_for(:module,
          name: %{"en" => "Gallery"},
          namespace: %{"en" => "Content"},
          help_text: %{"en" => "Help"},
          code: "{% ref refs.gallery %}",
          refs: [%{name: "gallery", uid: Brando.Utils.generate_uid(), data: %{type: "gallery", data: %{}}}]
        ),
        user
      )

    image = Factory.insert(:image, creator: user, title: %{"en" => "Library caption"})
    gallery = Factory.insert(:gallery)

    for sequence <- 0..1,
        do: Factory.insert(:gallery_object, gallery_id: gallery.id, image_id: image.id, sequence: sequence)

    page = Factory.insert(:page, creator: user)
    block = Brando.Test.insert_block(page, module, user: user, refs: %{"gallery" => gallery})

    {:ok, page: page, block: block, image: image}
  end

  defp put_overrides(block, overrides) do
    ref = Repo.get_by!(Ref, block_id: block.id, name: "gallery")
    data = %{ref.data | data: %{ref.data.data | gallery_object_overrides: overrides}}
    ref |> Ecto.Changeset.change(data: data) |> Repo.update!()
  end

  defp caption(image, text, placement \\ nil) do
    %GalleryObjectOverride{
      object_id: to_string(image.id),
      object_type: :image,
      placement: placement,
      title: text,
      use_default_title: false
    }
  end

  defp object_titles(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(".gallery-object .gallery-block-list-title, .gallery-object .gallery-tile")
    |> Enum.map(&Floki.text/1)
  end

  defp tile_captions(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(".gallery-object")
    |> Enum.map(fn object ->
      object |> Floki.find("input[name$='[title]']") |> Floki.attribute("value") |> List.first()
    end)
  end

  test "opens an entry whose gallery holds one image twice", c do
    {:ok, _view, html} = live(c.conn, "/admin/pages/update/#{c.page.id}")

    assert html |> Floki.parse_document!() |> Floki.find(".gallery-object") |> length() == 2
    assert object_titles(html) != []
  end

  test "each placement shows its own caption", c do
    put_overrides(c.block, [caption(c.image, "First caption", 0), caption(c.image, "Second caption", 1)])

    {:ok, _view, html} = live(c.conn, "/admin/pages/update/#{c.page.id}")

    assert tile_captions(html) == ["First caption", "Second caption"]
  end

  test "a caption stored for the image, before placements, shows on both", c do
    put_overrides(c.block, [caption(c.image, "Shared caption")])

    {:ok, _view, html} = live(c.conn, "/admin/pages/update/#{c.page.id}")

    assert tile_captions(html) == ["Shared caption", "Shared caption"]
  end
end
