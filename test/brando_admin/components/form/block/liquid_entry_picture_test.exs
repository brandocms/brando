defmodule BrandoAdmin.Components.Form.Block.LiquidEntryPictureTest do
  # A module whose code shows the entry's own picture, `{% picture
  # entry.cover {…} %}`, is previewed in the block editor with the entry's
  # image in place, or none: the entry may have no cover, or none loaded.
  use ExUnit.Case, async: false

  alias BrandoAdmin.Components.Form.Block

  @code ~s(<section class="top">{% picture entry.cover {size: "xlarge", lazyload: true} %}<h1>{{ entry.title }}</h1></section>)

  defp entry_picture(splits), do: Enum.find(splits, &match?({:entry_picture, _, _}, &1))

  test "an entry with a cover previews its image" do
    entry = %{title: "Frysja", cover: %Brando.Images.Image{path: "images/projects/cover/frysja.jpg"}}

    assert {:entry_picture, "entry.cover", src} = entry_picture(Block.liquid_splits(@code, [], entry))
    assert src == Brando.Utils.media_url("images/projects/cover/frysja.jpg")
  end

  test "a cover only the CDN has previews from the CDN" do
    original = Application.get_env(:brando, Brando.Images, [])

    Brando.Test.Support.put_test_env(
      Brando.Images,
      Keyword.put(original, :cdn, %{enabled: true, media_url: "https://cdn.example.com", keep_local_copy: false})
    )

    cover = %Brando.Images.Image{path: "images/projects/cover/frysja.jpg", cdn: true, config_target: "default"}

    assert {:entry_picture, "entry.cover", src} =
             entry_picture(Block.liquid_splits(@code, [], %{title: "Frysja", cover: cover}))

    assert src == "https://cdn.example.com/media/images/projects/cover/frysja.jpg"
  end

  test "an entry without a cover, or with none loaded, previews no image" do
    for cover <- [nil, %Ecto.Association.NotLoaded{__field__: :cover, __owner__: Brando.Pages.Page}] do
      assert {:entry_picture, "entry.cover", ""} =
               entry_picture(Block.liquid_splits(@code, [], %{title: "x", cover: cover}))
    end
  end

  test "a new entry, or a field the entry does not have, previews no image" do
    assert {:entry_picture, "entry.cover", ""} = entry_picture(Block.liquid_splits(@code, [], nil))

    code = ~s({% picture entry.no_such_field_anywhere {size: "xlarge"} %})
    assert {:entry_picture, "entry.no_such_field_anywhere", ""} = entry_picture(Block.liquid_splits(code, [], %{}))
  end

  test "the entry's picture follows the entry when it changes" do
    splits = Block.liquid_splits(@code, [], %{title: "Before", cover: nil})
    cover = %Brando.Images.Image{path: "images/projects/cover/after.jpg"}
    updated = Block.update_liquid_splits_entry_variables(splits, %{title: "After", cover: cover})

    assert {:entry_picture, "entry.cover", src} = entry_picture(updated)
    assert src == Brando.Utils.media_url("images/projects/cover/after.jpg")
    assert {:entry_variable, "title", "After"} in Enum.map(updated, &unsafe/1)
  end

  defp unsafe({:entry_variable, var, {:safe, value}}), do: {:entry_variable, var, IO.iodata_to_binary(value)}
  defp unsafe(split), do: split
end
