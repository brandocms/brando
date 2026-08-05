defmodule Brando.Content.BlockMediaAttrsTest do
  # Regression coverage for B4 — the cast lists that gate media on blocks.
  #
  # `@var_attrs` listed `image_id` and `file_id` but not `video_id`,
  # `gallery_id` or any of the config-target fields, though the editor renders
  # and commits all of them. `ref_changeset/3` had the same shape of hole:
  # `image_id`/`video_id`/`file_id` but no `gallery_id`. Anything omitted is
  # dropped silently by `cast/3` — no error, no warning, the value just never
  # reaches the database.
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Content.Block
  alias Brando.Factory
  alias Ecto.Changeset

  setup do
    user = Factory.insert(:random_user)
    page = Factory.insert(:page, creator: user)

    {:ok,
     user: user,
     page: page,
     image: Factory.insert(:image, creator: user),
     video: Factory.insert(:video),
     asset_file: insert_file(user),
     gallery: Factory.insert(:gallery)}
  end

  # no :file factory exists yet
  defp insert_file(user) do
    Brando.Repo.insert!(%Brando.Files.File{
      filename: "doc.pdf",
      filesize: 1234,
      mime_type: "application/pdf",
      config_target: "default",
      creator_id: user.id
    })
  end

  defp save_block(page, user, block_params) do
    params =
      Map.merge(
        %{
          "uid" => "mediablock",
          "type" => "module",
          "active" => true,
          "source" => "Elixir.Brando.Pages.Page.Blocks",
          "creator_id" => user.id
        },
        block_params
      )

    entry_block_cs =
      %Brando.Pages.Page.Blocks{}
      |> Map.put(:block, %Block{vars: [], refs: [], table_rows: [], children: [], block_identifiers: []})
      |> Brando.Pages.Page.Blocks.changeset(%{"entry_id" => page.id, "sequence" => 0, "block" => params}, user.id, true)
      |> Brando.Utils.set_action()

    {:ok, _} =
      page
      |> Brando.Repo.preload(:entry_blocks)
      |> Changeset.change()
      |> Changeset.put_assoc(:entry_blocks, [entry_block_cs])
      |> Brando.Repo.update()

    [entry_block] =
      Brando.Pages.Page.Blocks
      |> Brando.Repo.all()
      |> Brando.Repo.preload(block: [:vars, :refs])

    entry_block.block
  end

  describe "@var_attrs" do
    test "every media FK a var can carry is castable", ctx do
      %{page: page, user: user, image: image, video: video, asset_file: asset_file, gallery: gallery} = ctx

      block =
        save_block(page, user, %{
          "vars" => %{
            "0" => var_params("img", :image, %{"image_id" => image.id}),
            "1" => var_params("vid", :video, %{"video_id" => video.id}),
            "2" => var_params("fil", :file, %{"file_id" => asset_file.id}),
            "3" => var_params("gal", :gallery, %{"gallery_id" => gallery.id})
          }
        })

      by_key = Map.new(block.vars, &{&1.key, &1})

      assert by_key["img"].image_id == image.id
      assert by_key["vid"].video_id == video.id, "video_id was missing from @var_attrs"
      assert by_key["fil"].file_id == asset_file.id
      assert by_key["gal"].gallery_id == gallery.id, "gallery_id was missing from @var_attrs"
    end

    test "config targets on a media var are castable", ctx do
      %{page: page, user: user} = ctx

      block =
        save_block(page, user, %{
          "vars" => %{
            "0" =>
              var_params("gal", :gallery, %{
                "config_target" => "image:Brando.Pages.Page:cover",
                "gallery_image_config_target" => "image:Brando.Pages.Page:gallery",
                "gallery_video_config_target" => "video:Brando.Pages.Page:gallery",
                "gallery_allowed_types" => ["image", "video"]
              })
          }
        })

      [var] = block.vars

      assert var.config_target == "image:Brando.Pages.Page:cover",
             "config_target was missing from @var_attrs"

      assert var.gallery_image_config_target == "image:Brando.Pages.Page:gallery"
      assert var.gallery_video_config_target == "video:Brando.Pages.Page:gallery"
      assert var.gallery_allowed_types == [:image, :video]
    end

    test "var_attrs/0 covers every media and config field on the schema" do
      required = [
        :image_id,
        :video_id,
        :file_id,
        :gallery_id,
        :config_target,
        :gallery_image_config_target,
        :gallery_video_config_target,
        :gallery_allowed_types
      ]

      missing = required -- Block.var_attrs()
      assert missing == [], "var_attrs/0 is missing #{inspect(missing)}"
    end
  end

  describe "ref_changeset/3" do
    test "every media FK a ref can carry is castable", ctx do
      %{page: page, user: user, image: image, video: video, asset_file: asset_file, gallery: gallery} = ctx

      block =
        save_block(page, user, %{
          "refs" => %{
            "0" => ref_params("img", %{"image_id" => image.id}),
            "1" => ref_params("vid", %{"video_id" => video.id}),
            "2" => ref_params("fil", %{"file_id" => asset_file.id}),
            "3" => ref_params("gal", %{"gallery_id" => gallery.id})
          }
        })

      by_name = Map.new(block.refs, &{&1.name, &1})

      assert by_name["img"].image_id == image.id
      assert by_name["vid"].video_id == video.id
      assert by_name["fil"].file_id == asset_file.id
      assert by_name["gal"].gallery_id == gallery.id, "gallery_id was missing from ref_changeset/3"
    end
  end

  defp var_params(key, type, extra) do
    Map.merge(
      %{"type" => to_string(type), "key" => key, "label" => key, "placement" => "content", "width" => "full"},
      extra
    )
  end

  defp ref_params(name, extra) do
    Map.merge(
      %{
        "name" => name,
        "uid" => "ref#{name}0001",
        "description" => name,
        "data" => %{"type" => "text", "data" => %{"text" => "t", "type" => "paragraph"}}
      },
      extra
    )
  end
end
