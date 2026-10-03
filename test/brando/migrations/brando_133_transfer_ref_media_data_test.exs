defmodule Brando.Migrations.TransferRefMediaDataTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Factory
  alias BrandoIntegration.Repo

  @migration Application.app_dir(
               :brando,
               "priv/templates/brando.upgrade/migrations/brando_133_transfer_ref_media_data.exs"
             )

  setup_all do
    [{module, _bytecode}] = Code.compile_file(@migration)
    on_exit(fn -> :code.purge(module) && :code.delete(module) end)
    %{migration: module}
  end

  defp insert_ref(data) do
    %{rows: [[id]]} =
      Repo.query!(
        """
        INSERT INTO content_refs (name, uid, data, inserted_at, updated_at)
        VALUES ('ref', $1, $2, NOW(), NOW()) RETURNING id
        """,
        [Brando.Utils.generate_uid(), data]
      )

    id
  end

  defp image_id(ref_id) do
    %{rows: [[image_id]]} = Repo.query!("SELECT image_id FROM content_refs WHERE id = $1", [ref_id])
    image_id
  end

  test "links picture refs whose legacy path carries the media prefix", %{migration: migration} do
    prefixed = Factory.insert(:image, path: "images/site/posts/22081n278dnb.jpg")
    unprefixed = Factory.insert(:image, path: "images/site/posts/other.jpg")
    template = Factory.insert(:image, path: "images/site/posts/template.jpg")

    prefixed_ref = insert_ref(%{type: "picture", data: %{path: "/media/images/site/posts/22081n278dnb.jpg"}})
    unprefixed_ref = insert_ref(%{type: "picture", data: %{path: "images/site/posts/other.jpg"}})
    missing_ref = insert_ref(%{type: "picture", data: %{path: "/media/images/site/posts/gone.jpg"}})

    template_ref =
      insert_ref(%{type: "media", data: %{template_picture: %{path: "/media/images/site/posts/template.jpg"}}})

    Ecto.Migrator.up(Repo, System.unique_integer([:positive]), migration, log: false, migration_lock: false)

    assert image_id(prefixed_ref) == prefixed.id
    assert image_id(unprefixed_ref) == unprefixed.id
    assert image_id(missing_ref) == nil
    assert image_id(template_ref) == template.id
  end

  test "links gallery images whose legacy path or sizes carry the media prefix", %{migration: migration} do
    # Galleries without a block are credited to user 1.
    Repo.get(Brando.Users.User, 1) || Factory.insert(:random_user, id: 1)
    by_path = Factory.insert(:image, path: "images/site/gallery/by-path.jpg")
    by_size = Factory.insert(:image, path: "images/site/gallery/by-size.png")

    gallery_ref =
      insert_ref(%{
        type: "gallery",
        uid: Brando.Utils.generate_uid(),
        data: %{
          images: [
            %{path: "/media/images/site/gallery/by-path.jpg"},
            %{
              path: "/media/images/site/gallery/stale.jpg",
              sizes: %{small: "/media/images/site/gallery/small/by-size.jpg"}
            }
          ]
        }
      })

    Ecto.Migrator.up(Repo, System.unique_integer([:positive]), migration, log: false, migration_lock: false)

    %{rows: rows} =
      Repo.query!(
        """
        SELECT o.image_id FROM galleries_gallery_objects o
        JOIN content_refs r ON r.gallery_id = o.gallery_id
        WHERE r.id = $1 ORDER BY o.sequence
        """,
        [gallery_ref]
      )

    assert rows == [[by_path.id], [by_size.id]]
  end
end
