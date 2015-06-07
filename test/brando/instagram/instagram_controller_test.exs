#Code.require_file("router_helper.exs", Path.join([__DIR__, "..", ".."]))

defmodule Brando.Instagram.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.InstagramImage

  @img1 %{caption: "Caption1", created_time: "1432154962", id: 1, image: %Brando.Type.Image{credits: nil, optimized: false, path: "images/instagram/dummy_1.jpg", sizes: %{large: "images/instagram/large/dummy_1.jpg", thumb: "images/instagram/thumb/dummy_1.jpg"}, title: nil}, instagram_id: "dummy_1", link: "https://instagram.com/p/whatever1/", status: :approved, type: "image", url_original: "https://scontent.cdninstagram.com/hphotos-xaf1/t51.2885-15/e15/dummy_1.jpg", url_thumbnail: "https://scontent.cdninstagram.com/hphotos-xaf1/t51.2885-15/s150x150/e15/dummy_1.jpg", username: "username"}
  @img2 %{caption: "Caption2", created_time: "1432154963", id: 2, image: %Brando.Type.Image{credits: nil, optimized: false, path: "images/instagram/dummy_2.jpg", sizes: %{large: "images/instagram/large/dummy_2.jpg", thumb: "images/instagram/thumb/dummy_2.jpg"}, title: nil}, instagram_id: "dummy_2", link: "https://instagram.com/p/whatever2/", status: :rejected, type: "image", url_original: "https://scontent.cdninstagram.com/hphotos-xaf1/t51.2885-15/e15/dummy_2.jpg", url_thumbnail: "https://scontent.cdninstagram.com/hphotos-xaf1/t51.2885-15/s150x150/e15/dummy_2.jpg", username: "username"}
  @img3 %{caption: "Caption3", created_time: "1432154964", id: 3, image: %Brando.Type.Image{credits: nil, optimized: false, path: "images/instagram/dummy_3.jpg", sizes: %{large: "images/instagram/large/dummy_3.jpg", thumb: "images/instagram/thumb/dummy_3.jpg"}, title: nil}, instagram_id: "dummy_3", link: "https://instagram.com/p/whatever3/", status: :deleted, type: "image", url_original: "https://scontent.cdninstagram.com/hphotos-xaf1/t51.2885-15/e15/dummy_3.jpg", url_thumbnail: "https://scontent.cdninstagram.com/hphotos-xaf1/t51.2885-15/s150x150/e15/dummy_3.jpg", username: "username"}

  def create_images do
    InstagramImage.create(@img1)
    InstagramImage.create(@img2)
    InstagramImage.create(@img3)
  end

  test "index" do
    create_images
    conn =
      call(:get, "/admin/instagram/")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "<img data-id=\"1\" data-status=\"approved\" src=\"/media/images/instagram/thumb/dummy_1.jpg\" />"
    assert html_response(conn, 200) =~ "<img data-id=\"2\" data-status=\"approved\" src=\"/media/images/instagram/thumb/dummy_2.jpg\" />"
    assert html_response(conn, 200) =~ "<img data-id=\"3\" data-status=\"approved\" src=\"/media/images/instagram/thumb/dummy_3.jpg\" />"

    call(:post, "/admin/instagram/endre-status", %{ids: ["1", "2", "3"], status: "0"})
    |> with_user
    |> send_request

    conn =
      call(:get, "/admin/instagram/")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "<img data-id=\"1\" data-status=\"deleted\" src=\"/media/images/instagram/thumb/dummy_1.jpg\" />"
    assert html_response(conn, 200) =~ "<img data-id=\"2\" data-status=\"deleted\" src=\"/media/images/instagram/thumb/dummy_2.jpg\" />"
    assert html_response(conn, 200) =~ "<img data-id=\"3\" data-status=\"deleted\" src=\"/media/images/instagram/thumb/dummy_3.jpg\" />"

    call(:post, "/admin/instagram/endre-status", %{ids: ["1", "2", "3"], status: "1"})
    |> with_user
    |> send_request

    conn =
      call(:get, "/admin/instagram/")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "<img data-id=\"1\" data-status=\"rejected\" src=\"/media/images/instagram/thumb/dummy_1.jpg\" />"
    assert html_response(conn, 200) =~ "<img data-id=\"2\" data-status=\"rejected\" src=\"/media/images/instagram/thumb/dummy_2.jpg\" />"
    assert html_response(conn, 200) =~ "<img data-id=\"3\" data-status=\"rejected\" src=\"/media/images/instagram/thumb/dummy_3.jpg\" />"

    call(:post, "/admin/instagram/endre-status", %{ids: ["1", "2", "3"], status: "2"})
    |> with_user
    |> send_request

    conn =
      call(:get, "/admin/instagram/")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "<img data-id=\"1\" data-status=\"approved\" src=\"/media/images/instagram/thumb/dummy_1.jpg\" />"
    assert html_response(conn, 200) =~ "<img data-id=\"2\" data-status=\"approved\" src=\"/media/images/instagram/thumb/dummy_2.jpg\" />"
    assert html_response(conn, 200) =~ "<img data-id=\"3\" data-status=\"approved\" src=\"/media/images/instagram/thumb/dummy_3.jpg\" />"
  end
end