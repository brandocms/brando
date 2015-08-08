defmodule Brando.SocialTest do
  use ExUnit.Case, async: true
  use Plug.Test
  alias Brando.Social
  import Brando.HTML, only: [media_url: 0, img: 3]

  test "Facebook.link" do
    conn = conn(:get, "/awesome/link", [])
    assert Social.Facebook.link(conn, do: {:safe, "facebook"})
           == {:safe, ["<a href=\"https://www.facebook.com/sharer/sharer.php?u=http%3A%2F%2Fwww.example.com%2Fawesome%2Flink\" title=\"facebook\">", "facebook", "</a>"]}
  end

  test "Twitter.link" do
    conn = conn(:get, "/awesome/link", [])
    assert Social.Twitter.link(conn, "Twitter text", do: {:safe, "twitter"})
           == {:safe, ["<a href=\"https://twitter.com/intent/tweet?url=http%3A%2F%2Fwww.example.com%2Fawesome%2Flink&amp;text=Twitter+text\" title=\"twitter\">", "twitter", "</a>"]}
  end

  test "Pinterest.link" do
    image = %{sizes: %{"xlarge" => "images/xlarge/file.jpg"}}
    conn = conn(:get, "/awesome/link", [])
    assert Social.Pinterest.link(conn, img(image, :xlarge, [prefix: media_url()]), "Pinterest text", do: {:safe, "pinterest"})
           == {:safe, ["<a href=\"https://pinterest.com/pin/create/button/?url=http%3A%2F%2Fwww.example.com%2Fawesome%2Flink&amp;media=http%3A%2F%2Fwww.example.com%2Fmedia%2Fimages%2Fxlarge%2Ffile.jpg&amp;description=Pinterest+text&quot;\" title=\"pinterest\">", "pinterest", "</a>"]}
  end
end