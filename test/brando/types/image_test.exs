defmodule Brando.Types.ImageTest do
  use ExUnit.Case
  alias Brando.Type.Image

  @raw %{
    "credits" => "Credits",
    "path" => "images/avatars/27i97a.jpeg",
    "title" => nil,
    "sizes" => %{
      "medium" => "images/avatars/medium/27i97a.jpeg",
      "thumb" => "images/avatars/thumb/27i97a.jpeg"
    }
  }

  @result %Image{
    credits: "Credits",
    path: "images/avatars/27i97a.jpeg",
    title: nil,
    sizes: %{
      "medium" => "images/avatars/medium/27i97a.jpeg",
      "thumb" => "images/avatars/thumb/27i97a.jpeg"
    }
  }

  @struct %Image{}

  test "cast" do
    assert Image.cast(@raw) == {:ok, @result}
    assert Image.cast(@struct) == {:ok, @struct}
  end

  test "blank?" do
    assert Image.blank?(@raw) == @struct
  end

  test "load" do
    assert Image.load(@raw) == {:ok, @result}
  end

  test "dump" do
    assert Image.dump(@result) ==
             {:ok,
              %Brando.Type.Image{
                credits: "Credits",
                focal: %{"x" => 50, "y" => 50},
                height: nil,
                path: "images/avatars/27i97a.jpeg",
                sizes: %{
                  "medium" => "images/avatars/medium/27i97a.jpeg",
                  "thumb" => "images/avatars/thumb/27i97a.jpeg"
                },
                title: nil,
                width: nil
              }}
  end
end
