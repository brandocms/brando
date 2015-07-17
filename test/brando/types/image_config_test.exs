defmodule Brando.Types.ImageConfigTest do
  use ExUnit.Case
  alias Brando.Type.ImageConfig

  @result %{allowed_mimetypes: ["image/jpeg", "image/png"], default_size: "medium", size_limit: 10240000,
                  sizes: %{large: %{quality: 100, size: "700"}, medium: %{quality: 100, size: "500"}, small: %{quality: 100, size: "300"},
                           thumb: %{crop: true, quality: 100, size: "150x150"}, xlarge: %{quality: 100, size: "900"}},
                  upload_path: "images/default"}
  @result2 %Brando.Type.ImageConfig{allowed_mimetypes: ["image/jpeg", "image/png"], default_size: "medium",
             random_filename: false, size_limit: 10240000,
             sizes: %{"large" => %{"quality" => 100, "size" => "700"},
               "medium" => %{"quality" => 100, "size" => "500"},
               "small" => %{"quality" => 100, "size" => "300"},
               "thumb" => %{"crop" => true, "quality" => 100, "size" => "150x150"},
               "xlarge" => %{"quality" => 100, "size" => "900"}}, upload_path: "images/result2"}
  @struct %ImageConfig{}
  @map %{"allowed_mimetypes" => ["image/jpeg", "image/png"], "default_size" => "medium",
         "random_filename" => false, "size_limit" => 10240000,
         "sizes" => %{"large" => %{"quality" => 100, "size" => "700"},
                      "medium" => %{"quality" => 100, "size" => "500"},
                      "small" => %{"quality" => 100, "size" => "300"},
                      "thumb" => %{"crop" => true, "quality" => 100, "size" => "150x150"},
                      "xlarge" => %{"quality" => 100, "size" => "900"}}, "upload_path" => "images/result2"}

  test "cast" do
    assert ImageConfig.cast(@struct) == {:ok, @struct}
  end

  test "blank?" do
    assert ImageConfig.blank?(@struct) == @struct
  end

  test "load" do
    assert ImageConfig.load(@map) == {:ok, @result2}
  end

  test "dump" do
    assert ImageConfig.dump(@struct) == {:ok, @struct}
  end
end