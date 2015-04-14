defmodule Brando.Types.ImageConfigTest do
  use ExUnit.Case
  alias Brando.Type.Image.Config

  @raw "{\"upload_path\":\"images/default\",\"sizes\":{\"xlarge\":{\"size\":\"900\",\"quality\":100},\"thumb\":{\"size\":\"150x150^ -gravity center -extent 150x150\",\"quality\":100,\"crop\":true},\"small\":{\"size\":\"300\",\"quality\":100},\"medium\":{\"size\":\"500\",\"quality\":100},\"large\":{\"size\":\"700\",\"quality\":100}},\"size_limit\":10240000,\"default_size\":\"medium\",\"allowed_mimetypes\":[\"image/jpeg\",\"image/png\"]}"
  @result %Config{allowed_mimetypes: ["image/jpeg", "image/png"], default_size: "medium", size_limit: 10240000,
                  sizes: %{large: %{quality: 100, size: "700"}, medium: %{quality: 100, size: "500"}, small: %{quality: 100, size: "300"},
                           thumb: %{crop: true, quality: 100, size: "150x150^ -gravity center -extent 150x150"}, xlarge: %{quality: 100, size: "900"}},
                  upload_path: "images/default"}
  @struct %Config{}

  test "cast" do
    assert Config.cast(@raw) == {:ok, @result}
    assert Config.cast(@struct) == {:ok, @struct}
  end

  test "blank?" do
    assert Config.blank?(@raw) == @struct
  end

  test "load" do
    assert Config.load("[]") == {:ok, @struct}
    assert Config.load(@raw) == {:ok, @result}
  end

  test "dump" do
    assert Config.dump(@struct) == {:ok, @raw}
  end
end