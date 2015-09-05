#Code.require_file("router_helper.exs", Path.join([__DIR__, "..", ".."]))

defmodule Brando.Instagram.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper
  alias Brando.InstagramImage

  @img1 %{"caption" => "Caption1", "created_time" => "1432154962",
          "image" => %Brando.Type.Image{credits: nil, optimized: false,
          path: "images/instagram/dummy_1.jpg",
          sizes: %{large: "images/instagram/large/dummy_1.jpg",
          thumb: "images/instagram/thumb/dummy_1.jpg"}, title: nil},
          "instagram_id" => "dummy_1",
          "link" => "https://instagram.com/p/whatever1/",
          "status" => :approved, "type" => "image",
          "url_original" => "https://scontent.cdninstagram.com/" <>
          "hphotos-xaf1/t51.2885-15/e15/dummy_1.jpg",
          "url_thumbnail" => "https://scontent.cdninstagram.com/" <>
          "hphotos-xaf1/t51.2885-15/s150x150/e15/dummy_1.jpg",
          "username" => "username"}
  @img2 %{"caption" => "Caption2", "created_time" => "1432154963",
          "image" => %Brando.Type.Image{credits: nil, optimized: false,
          path: "images/instagram/dummy_2.jpg",
          sizes: %{large: "images/instagram/large/dummy_2.jpg",
          thumb: "images/instagram/thumb/dummy_2.jpg"}, title: nil},
          "instagram_id" => "dummy_2",
          "link" => "https://instagram.com/p/whatever2/",
          "status" => :rejected, "type" => "image",
          "url_original" => "https://scontent.cdninstagram.com/" <>
          "hphotos-xaf1/t51.2885-15/e15/dummy_2.jpg",
          "url_thumbnail" => "https://scontent.cdninstagram.com/" <>
          "hphotos-xaf1/t51.2885-15/s150x150/e15/dummy_2.jpg",
          "username" => "username"}
  @img3 %{"caption" => "Caption3", "created_time" => "1432154964",
          "image" => %Brando.Type.Image{credits: nil, optimized: false,
          path: "images/instagram/dummy_3.jpg",
          sizes: %{large: "images/instagram/large/dummy_3.jpg",
          thumb: "images/instagram/thumb/dummy_3.jpg"}, title: nil},
          "instagram_id" => "dummy_3",
          "link" => "https://instagram.com/p/whatever3/",
          "status" => :deleted, "type" => "image",
          "url_original" => "https://scontent.cdninstagram.com/" <>
          "hphotos-xaf1/t51.2885-15/e15/dummy_3.jpg",
          "url_thumbnail" => "https://scontent.cdninstagram.com/" <>
          "hphotos-xaf1/t51.2885-15/s150x150/e15/dummy_3.jpg",
          "username" => "username"}

  def create_images do
    InstagramImage.create(@img1)
    InstagramImage.create(@img2)
    InstagramImage.create(@img3)
  end

  test "index" do
    create_images
    conn =
      :get
      |> call("/admin/instagram/")
      |> with_user
      |> send_request

    assert html_response(conn, 200)
           =~ "data-status=\"approved\" " <>
              "src=\"/media/images/instagram/thumb/dummy_1.jpg\""
    assert html_response(conn, 200)
           =~ "data-status=\"approved\" " <>
              "src=\"/media/images/instagram/thumb/dummy_2.jpg\""
    assert html_response(conn, 200)
           =~ "data-status=\"approved\" " <>
              "src=\"/media/images/instagram/thumb/dummy_3.jpg\""

    ids =
      InstagramImage
      |> Ecto.Query.select([i], i.id)
      |> Brando.repo.all
      |> Enum.map(&Integer.to_string/1)

    :post
    |> call("/admin/instagram/change-status", %{ids: ids, status: "0"})
    |> with_user
    |> send_request

    conn =
      :get
      |> call("/admin/instagram/")
      |> with_user
      |> send_request

    assert html_response(conn, 200)
           =~ "data-status=\"deleted\" " <>
              "src=\"/media/images/instagram/thumb/dummy_1.jpg\""
    assert html_response(conn, 200)
           =~ "data-status=\"deleted\" " <>
              "src=\"/media/images/instagram/thumb/dummy_2.jpg\""
    assert html_response(conn, 200)
           =~ "data-status=\"deleted\" " <>
              "src=\"/media/images/instagram/thumb/dummy_3.jpg\""

    :post
    |> call("/admin/instagram/change-status", %{ids: ids, status: "1"})
    |> with_user
    |> send_request

    conn =
      :get
      |> call("/admin/instagram/")
      |> with_user
      |> send_request

    assert html_response(conn, 200)
           =~ "data-status=\"rejected\" " <>
               "src=\"/media/images/instagram/thumb/dummy_1.jpg\""
    assert html_response(conn, 200)
           =~ "data-status=\"rejected\" " <>
               "src=\"/media/images/instagram/thumb/dummy_2.jpg\""
    assert html_response(conn, 200)
           =~ "data-status=\"rejected\" " <>
               "src=\"/media/images/instagram/thumb/dummy_3.jpg\""

    :post
    |> call("/admin/instagram/change-status", %{ids: ids, status: "2"})
    |> with_user
    |> send_request

    conn =
      :get
      |> call("/admin/instagram/")
      |> with_user
      |> send_request

    assert html_response(conn, 200)
           =~ "data-status=\"approved\" " <>
              "src=\"/media/images/instagram/thumb/dummy_1.jpg\""
    assert html_response(conn, 200)
           =~ "data-status=\"approved\" " <>
              "src=\"/media/images/instagram/thumb/dummy_2.jpg\""
    assert html_response(conn, 200)
           =~ "data-status=\"approved\" " <>
              "src=\"/media/images/instagram/thumb/dummy_3.jpg\""
  end
end
