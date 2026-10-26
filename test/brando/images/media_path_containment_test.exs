defmodule Brando.Images.MediaPathContainmentTest do
  # A media record's stored path names a file under the media root, and every
  # file operation keyed on it stays there. A row whose path climbs out (one
  # written before paths were validated, or by hand) is refused, not followed:
  # the crop editor wrote its upload to wherever an image's path pointed.
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Images
  alias Brando.Images.Crop
  alias Brando.Tenant.Storage

  setup do
    user = Factory.insert(:random_user, role: :superuser)
    outside = Path.join(System.tmp_dir!(), "brando-containment-#{System.unique_integer([:positive])}")
    File.mkdir_p!(outside)
    on_exit(fn -> File.rm_rf(outside) end)

    %{user: user, outside: outside, escape: escaping(Path.join(outside, "marker.jpg"))}
  end

  # `target`, an absolute path, as a path relative to the media root
  defp escaping(target) do
    depth = Storage.current_media_root() |> Path.expand() |> Path.split() |> length()
    String.duplicate("../", depth) <> String.trim_leading(target, "/")
  end

  describe "Storage.media_file/1" do
    test "joins a relative path with the media root" do
      root = Storage.current_media_root()
      assert Storage.media_file("images/a.jpg") == {:ok, Path.join(root, "images/a.jpg")}
      assert Storage.media_file("images/../a.jpg") == {:ok, Path.join(root, "images/../a.jpg")}
    end

    test "refuses a path that leaves the media root", %{escape: escape} do
      for path <- [escape, "../a.jpg", "images/../../a.jpg", "/etc/passwd", "~/a.jpg", "~", "a\0.jpg", nil] do
        assert Storage.media_file(path) == :error, "#{inspect(path)} was accepted"
        refute Storage.safe_media_path?(path)
      end
    end
  end

  describe "the image changeset" do
    test "rejects a path or a size that leaves the media root", %{user: user, escape: escape} do
      image = Factory.insert(:image)

      changeset = Images.Image.changeset(image, %{path: escape}, user)
      assert {"is invalid", [validation: :media_path]} = changeset.errors[:path]

      changeset = Images.Image.changeset(image, %{sizes: %{"thumb" => "../thumb.jpg"}}, user)
      assert {"is invalid", [validation: :media_path]} = changeset.errors[:sizes]

      assert Images.Image.changeset(image, %{path: "images/other.jpg"}, user).valid?
    end

    test "a file's name may not leave the media root", %{user: user} do
      file = %Brando.Files.File{filename: "a.pdf", mime_type: "application/pdf", filesize: 1, config_target: "default"}
      assert Brando.Files.File.changeset(file, %{filename: "../../a.pdf"}, user).errors[:filename]
      refute Brando.Files.File.changeset(file, %{filename: "b.pdf"}, user).errors[:filename]
    end
  end

  test "replacing a crop on a row whose path leaves the root writes nothing", ctx do
    image = Factory.insert(:image, path: ctx.escape)
    marker = Path.join(ctx.outside, "marker.jpg")

    assert {:error, :unsafe_media_path} = Crop.save_replace(image, "MARKER", %{x: 10, y: 20}, ctx.user)
    refute File.exists?(marker)
    assert Repo.get!(Images.Image, image.id).path == ctx.escape

    # The endpoint the image editor posts to reports it as an error
    upload = Path.join(ctx.outside, "upload.jpg")
    File.write!(upload, "MARKER")

    conn =
      Phoenix.ConnTest.build_conn()
      |> Plug.Conn.assign(:current_user, ctx.user)
      |> BrandoAdmin.API.Content.Upload.ImageController.replace_crop(%{
        "image_id" => to_string(image.id),
        "image" => %Plug.Upload{path: upload, filename: "upload.jpg", content_type: "image/jpeg"},
        "focal_x" => "10",
        "focal_y" => "20"
      })

    assert %{"status" => 500} = Jason.decode!(conn.resp_body)
    refute File.exists?(marker)
  end

  test "a crop saved as a new copy of such a row writes nothing", ctx do
    image = Factory.insert(:image, path: ctx.escape)

    assert {:error, %Ecto.Changeset{}} = Crop.save_as_new_copy(image, "MARKER", %{x: 10, y: 20}, ctx.user)
    assert File.ls!(ctx.outside) == []
  end

  test "deleting such a row's files deletes nothing outside the root", ctx do
    original = Path.join(ctx.outside, "marker.jpg")
    sized = Path.join(ctx.outside, "thumb.jpg")
    File.write!(original, "keep")
    File.write!(sized, "keep")

    image = %Images.Image{path: ctx.escape, formats: nil, sizes: %{"thumb" => escaping(sized)}}

    assert Images.Utils.delete_media(ctx.escape) == {:error, :unsafe_media_path}
    assert {:ok, _} = Images.Utils.delete_original_and_sized_images(image)
    assert File.read!(original) == "keep"
    assert File.read!(sized) == "keep"
  end

  test "duplicating such a row copies nothing", ctx do
    File.write!(Path.join(ctx.outside, "marker.jpg"), "secret")
    image = Factory.insert(:image, path: ctx.escape)

    assert Images.duplicate_image(image.id, ctx.user) == {:error, :unsafe_media_path}
    assert File.ls!(ctx.outside) == ["marker.jpg"]
  end

  test "media_path/1 raises rather than resolve such a path", %{escape: escape} do
    assert_raise ArgumentError, fn -> Images.Utils.media_path(escape) end
  end
end
