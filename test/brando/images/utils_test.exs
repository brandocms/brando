defmodule Brando.Images.UtilsTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Plug.Test
  use RouterHelper

  import Brando.Images.Utils
  alias Brando.Factory

  test "size_dir/2 binary" do
    assert size_dir("test/dir/filename.jpg", "thumb") == "test/dir/thumb/filename.jpg"
  end

  test "size_dir/2 atom" do
    assert size_dir("test/dir/filename.jpg", :thumb) == "test/dir/thumb/filename.jpg"
  end

  test "media_path" do
    assert media_path() == Brando.config(:media_path)
    assert media_path(nil) == Brando.config(:media_path)
    assert media_path("images") == Path.join(Brando.config(:media_path), "images")
  end

  test "put_size_cfg" do
    File.rm_rf!(Brando.config(:media_path))
    File.mkdir_p!(Brando.config(:media_path))

    user      = Factory.insert(:user)
    category  = Factory.insert(:image_category, creator: user)
    series    = Factory.insert(:image_series, creator: user, image_category: category)
    up_params = Factory.build(:plug_upload)

    :post
    |> call("/admin/images/series/#{series.id}/upload", %{"id" => series.id, "image" => up_params})
    |> with_user(user)
    |> as_json
    |> send_request

    put_size_cfg(series, "medium", %{"portrait" => %{"size" => "500", "quality" => 1},
                                     "landscape" => %{"size" => "50", "quality" => 1}})

    series = Brando.repo.get(Brando.ImageSeries, series.id)

    assert series.cfg.sizes == %{
      "medium" => %{
        "landscape" => %{"quality" => 1, "size" => "50"},
        "portrait" => %{"quality" => 1, "size" => "500"}
      },
      "small" => %{"quality" => 1, "size" => "300"},
      "thumb" => %{"crop" => true, "quality" => 1, "size" => "150x150"}
    }
  end
end
