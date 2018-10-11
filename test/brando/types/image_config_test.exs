defmodule Brando.Types.ImageConfigTest do
  use ExUnit.Case
  alias Brando.Type.ImageConfig

  @result2 %Brando.Type.ImageConfig{
    allowed_mimetypes: ["image/jpeg", "image/png"],
    default_size: "medium",
    random_filename: false,
    size_limit: 10_240_000,
    sizes: %{
      "large" => %{"quality" => 100, "size" => "700"},
      "medium" => %{"quality" => 100, "size" => "500"},
      "small" => %{"quality" => 100, "size" => "300"},
      "thumb" => %{"crop" => true, "quality" => 100, "size" => "150x150"},
      "xlarge" => %{"quality" => 100, "size" => "900"}
    },
    upload_path: "images/result2"
  }
  @struct %ImageConfig{}
  @map %{
    "allowed_mimetypes" => ["image/jpeg", "image/png"],
    "default_size" => "medium",
    "random_filename" => false,
    "size_limit" => 10_240_000,
    "sizes" => %{
      "large" => %{"quality" => 100, "size" => "700"},
      "medium" => %{"quality" => 100, "size" => "500"},
      "small" => %{"quality" => 100, "size" => "300"},
      "thumb" => %{"crop" => true, "quality" => 100, "size" => "150x150"},
      "xlarge" => %{"quality" => 100, "size" => "900"}
    },
    "upload_path" => "images/result2"
  }

  test "cast" do
    assert ImageConfig.cast(
             ~s({"upload_path":"images/default","sizes":{"xlarge":{"size":"900","quality":100},"thumb":{"size":"150x150","quality":100,"crop":true},"small":{"size":"300","quality":100},"micro":{"size":"25x25","quality":100,"crop":true},"medium":{"size":"500","quality":100},"large":{"size":"700","quality":100}},"size_limit":10240000,"random_filename":true,"default_size":"medium","allowed_mimetypes":["image/jpeg","image/png"]})
           ) ==
             {:ok,
              %Brando.Type.ImageConfig{
                allowed_mimetypes: ["image/jpeg", "image/png"],
                default_size: "medium",
                random_filename: true,
                size_limit: 10_240_000,
                sizes: %{
                  "large" => %{
                    "quality" => 100,
                    "size" => "700"
                  },
                  "medium" => %{
                    "quality" => 100,
                    "size" => "500"
                  },
                  "micro" => %{
                    "crop" => true,
                    "quality" => 100,
                    "size" => "25x25"
                  },
                  "small" => %{
                    "quality" => 100,
                    "size" => "300"
                  },
                  "thumb" => %{
                    "crop" => true,
                    "quality" => 100,
                    "size" => "150x150"
                  },
                  "xlarge" => %{
                    "quality" => 100,
                    "size" => "900"
                  }
                },
                upload_path: "images/default"
              }}

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
