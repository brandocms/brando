defmodule Brando.SocialTest do
  use ExUnit.Case, async: true
  use Plug.Test

  import Brando.Utils, only: [media_url: 0, img_url: 3]

  alias Brando.Social

  test "Facebook.link" do
    conn = conn(:get, "/awesome/link", [])
    assert Social.Facebook.link(conn, do: {:safe, "facebook"})
           == {:safe,
               ["<a href=\"https://www.facebook.com/sharer/sharer.php?" <>
                "u=http%3A%2F%2Fwww.example.com%2Fawesome%2Flink\" " <>
                "title=\"facebook\">", "facebook", "</a>"]}
  end

  test "Twitter.link" do
    conn = conn(:get, "/awesome/link", [])
    assert Social.Twitter.link(conn, "Twitter text", do: {:safe, "twitter"})
           == {:safe,
               ["<a href=\"https://twitter.com/intent/tweet?url=http%3" <>
                "A%2F%2Fwww.example.com%2Fawesome%2Flink&amp;text=Twitte" <>
                "r+text\" title=\"twitter\">", "twitter", "</a>"]}
  end

  test "Pinterest.link" do
    image = %{sizes: %{"xlarge" => "images/xlarge/file.jpg"}}
    conn = conn(:get, "/awesome/link", [])
    link = Social.Pinterest.link(conn, img_url(image, :xlarge,
                                 [prefix: media_url()]), "Pinterest text",
                                 do: {:safe, "pinterest"})
    assert link
           == {:safe,
               ["<a href=\"https://pinterest.com/pin/create/button/?ur" <>
                "l=http%3A%2F%2Fwww.example.com%2Fawesome%2Flink&amp;med" <>
                "ia=http%3A%2F%2Fwww.example.com%2Fmedia%2Fimages%2Fxlar" <>
                "ge%2Ffile.jpg&amp;description=Pinterest+text&quot;\" " <>
                "title=\"pinterest\">", "pinterest", "</a>"]}
  end
end