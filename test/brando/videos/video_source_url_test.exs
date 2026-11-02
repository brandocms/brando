defmodule Brando.Videos.VideoSourceURLTest do
  @moduledoc """
  A video's address is http(s) or has no scheme. The browser strips whitespace
  and control characters before it reads a scheme, so the check does too.
  """
  use ExUnit.Case, async: false
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Videos.Video

  defp changeset(url, data \\ %Video{}) do
    Video.changeset(data, %{type: :youtube, source_url: url}, :system)
  end

  for url <- [
        "javascript:document.title='f05'",
        "JaVaScRiPt:document.title='f05'",
        " javascript:document.title='f05'",
        "\tjava\nscript:document.title='f05'",
        "\u0001javascript:document.title='f05'",
        "java\u0000script:document.title='f05'",
        "\u007Fjavascript:document.title='f05'",
        "data:text/html,clip",
        "vbscript:clip",
        "blob:https://example.com/clip",
        "file:///etc/clip.mp4",
        "ftp://example.com/clip.mp4"
      ] do
    test "refuses #{inspect(url)}" do
      changeset = changeset(unquote(url))

      refute changeset.valid?
      assert Keyword.has_key?(changeset.errors, :source_url)
    end
  end

  for url <- [
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
        "HTTPS://youtu.be/dQw4w9WgXcQ",
        "http://example.com/clip.mp4",
        "https://example.com/a:b/clip.mp4",
        "  https://example.com/clip.mp4\n",
        "vimeo.com/76979871",
        "//vimeo.com/76979871",
        "example.com/a:b/clip.mp4",
        "example.com/clip.mp4?at=1:30",
        "/media/clip.mp4"
      ] do
    test "accepts #{inspect(url)}" do
      assert changeset(unquote(url)).valid?
    end
  end

  test "accepts no address" do
    assert changeset(nil).valid?
  end

  test "a row with a stored address can still be saved for another change" do
    video = %Video{type: :youtube, source_url: "javascript:document.title='f05'"}

    assert Video.changeset(video, %{title: "Renamed"}, :system).valid?
  end

  test "an editor can't store it through the form's path" do
    user = Factory.insert(:random_user)

    assert {:error, %Ecto.Changeset{} = changeset} =
             Brando.Videos.create_video(%{type: :youtube, source_url: "javascript:document.title='f05'"}, user)

    assert Keyword.has_key?(changeset.errors, :source_url)
  end

  test "allowed?/1 is what the admin's links ask" do
    assert Video.ValidSourceURL.allowed?("https://example.com/clip.mp4")
    assert Video.ValidSourceURL.allowed?("vimeo.com/76979871")
    refute Video.ValidSourceURL.allowed?("java\nscript:document.title='f05'")
    refute Video.ValidSourceURL.allowed?(nil)
  end
end
