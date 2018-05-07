defmodule Brando.SocialTest do
  use ExUnit.Case, async: true
  use Plug.Test

  import Brando.Utils, only: [media_url: 0, img_url: 3]

  alias Brando.Social

  test "Facebook.link" do
    conn = conn(:get, "/awesome/link", [])
    assert Social.Facebook.link(conn, do: {:safe, "facebook"})
          |> Phoenix.HTML.safe_to_string
           == "<a href=\"https://www.facebook.com/sharer/sharer.php?u=http%3A%2F%2Flocalhost%2Fawesome%2Flink\" title=\"facebook\">facebook</a>"
  end

  test "Twitter.link" do
    conn = conn(:get, "/awesome/link", [])
    assert Social.Twitter.link(conn, "Twitter text", do: {:safe, "twitter"})
           |> Phoenix.HTML.safe_to_string
           == "<a href=\"https://twitter.com/intent/tweet?url=http%3A%2F%2Flocalhost%2Fawesome%2Flink&amp;text=Twitter+text\" title=\"twitter\">twitter</a>"
  end

  test "Pinterest.link" do
    image = %{sizes: %{"xlarge" => "images/xlarge/file.jpg"}}
    conn = conn(:get, "/awesome/link", [])
    link = Social.Pinterest.link(conn, img_url(image, :xlarge,
                                 [prefix: media_url()]), "Pinterest text",
                                 do: {:safe, "pinterest"})
    assert link |> Phoenix.HTML.safe_to_string
           == "<a href=\"https://pinterest.com/pin/create/button/?url=http%3A%2F%2Flocalhost%2Fawesome%2Flink&amp;media=http%3A%2F%2Flocalhost%2Fmedia%2Fimages%2Fxlarge%2Ffile.jpg&amp;description=Pinterest+text&quot;\" title=\"pinterest\">pinterest</a>"
  end

  test "Email.link" do
    conn = conn(:get, "/awesome/link", [])
    assert Social.Email.link(conn, "Subject", do: {:safe, "email"}) |> Phoenix.HTML.safe_to_string
           == "<a href=\"mailto:?subject=Subject&amp;body=http://localhost/awesome/link\" title=\"email\">email</a>"
  end
end
