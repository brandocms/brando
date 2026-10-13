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

    on_exit(fn ->
      :code.purge(module)
      :code.delete(module)
    end)

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
    assert image_id(template_ref) == template.id

    # 0.53 showed it from the ref's own data, so its row is made from that
    assert %{path: "images/site/posts/gone.jpg", formats: [:jpg]} =
             Repo.get!(Brando.Images.Image, image_id(missing_ref))
  end

  defp ref_data(ref_id) do
    %{rows: [[data]]} = Repo.query!("SELECT data->'data' FROM content_refs WHERE id = $1", [ref_id])
    data
  end

  test "an exact path wins over an image its sizes name by stem", %{migration: migration} do
    # Two images sharing a stem, and an SVG whose sizes point at itself, so
    # dropping the size folder names another image
    png = Factory.insert(:image, path: "images/site/posts/team.png")
    jpg = Factory.insert(:image, path: "images/site/posts/team.jpg")
    other_logo = Factory.insert(:image, path: "images/site/logo.png")
    svg = Factory.insert(:image, path: "images/site/posts/logo.svg")

    team =
      insert_ref(%{
        type: "picture",
        data: %{path: "images/site/posts/team.jpg", sizes: %{small: "images/site/posts/small/team.jpg"}}
      })

    logo =
      insert_ref(%{
        type: "picture",
        data: %{path: "images/site/posts/logo.svg", sizes: %{small: "images/site/posts/logo.svg"}}
      })

    Ecto.Migrator.up(Repo, System.unique_integer([:positive]), migration, log: false, migration_lock: false)

    assert image_id(team) == jpg.id
    assert image_id(logo) == svg.id
    refute image_id(team) == png.id
    refute image_id(logo) == other_logo.id
  end

  test "a stale path is not linked when the image its sizes name has no row", %{migration: migration} do
    # 0.53 showed B, from the sizes; A is what the stale path names
    Factory.insert(:image, path: "images/site/posts/a.jpg")

    ref =
      insert_ref(%{
        type: "picture",
        data: %{path: "images/site/posts/a.jpg", sizes: %{small: "images/site/posts/small/b.jpg"}}
      })

    Ecto.Migrator.up(Repo, System.unique_integer([:positive]), migration, log: false, migration_lock: false)

    assert image_id(ref) == nil
    # The data stays for the check to report and an editor to settle
    assert %{"path" => "images/site/posts/a.jpg", "sizes" => %{"small" => "images/site/posts/small/b.jpg"}} =
             ref_data(ref)
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
