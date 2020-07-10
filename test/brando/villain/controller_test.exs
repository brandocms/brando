defmodule Brando.Villain.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.API.Villain.VillainController

  @up_error %Plug.Upload{
    content_type: "image/png",
    filename: "sample.png",
    path: Path.expand("../", __DIR__) <> "/fixtures/sample.png"
  }

  @up %Plug.Upload{
    content_type: "image/png",
    filename: "sample.png",
    path: Path.expand("../../", __DIR__) <> "/fixtures/sample.png"
  }

  test "browse_images", %{conn: conn} do
    conn = VillainController.browse_images(conn, %{"slug" => "test"})
    assert conn.resp_body == "{\"images\":[],\"status\":204}"

    is1 = Factory.insert(:image_series, name: "series", slug: "series")
    _i1 = Factory.insert(:image, image_series_id: is1.id)
    _i2 = Factory.insert(:image, image_series_id: is1.id)

    conn = recycle(conn)
    conn = VillainController.browse_images(conn, %{"slug" => "series"})

    resp_map = Jason.decode!(conn.resp_body)
    assert Enum.count(resp_map["images"]) == 2
    assert resp_map["status"] == 200
  end

  test "templates", %{conn: conn} do
    conn = VillainController.templates(conn, %{"slug" => "test"})
    assert conn.resp_body == "[]"

    Factory.insert(:template)
    Factory.insert(:template)

    conn = recycle(conn)
    conn = VillainController.templates(conn, %{"slug" => "all"})

    resp_map = Jason.decode!(conn.resp_body)
    assert Enum.count(resp_map) == 2
  end

  test "store_template", %{conn: conn} do
    t1 = Factory.insert(:template)
    encoded_t1 = Jason.encode!(%{"data" => t1})
    conn = VillainController.store_template(conn, %{"template" => encoded_t1})
    resp_map = Jason.decode!(conn.resp_body)
    assert resp_map["status"] == 200
  end

  test "upload", %{conn: conn} do
    _is1 = Factory.insert(:image_series, name: "test", slug: "test")

    conn =
      VillainController.upload_image(conn, %{
        "uid" => "test1234",
        "slug" => "test",
        "image" => @up_error,
        "name" => "hepp.jpg"
      })

    resp_map = Jason.decode!(conn.resp_body)
    assert resp_map["status"] == 500

    conn = recycle(conn)

    conn =
      VillainController.upload_image(conn, %{
        "uid" => "test1234",
        "slug" => "test",
        "image" => @up,
        "name" => "hepp.jpg"
      })

    resp_map = Jason.decode!(conn.resp_body)
    assert resp_map["status"] == 200
    assert resp_map["uid"] == "test1234"

    conn = recycle(conn)

    conn =
      VillainController.upload_image(conn, %{
        "uid" => "test1234",
        "slug" => "non_existing",
        "image" => @up,
        "name" => "hepp.jpg"
      })

    resp_map = Jason.decode!(conn.resp_body)
    assert resp_map["status"] == 500

    assert resp_map["error"] ==
             "Image series `non_existing` not found. Make sure it exists before using it as an upload target"
  end

  test "delete_template", %{conn: conn} do
    t1 = Factory.insert(:template)
    conn = VillainController.delete_template(conn, %{"id" => t1.id})
    resp_map = Jason.decode!(conn.resp_body)
    assert resp_map["status"] == 200
  end

  test "sequence_templates", %{conn: conn} do
    t1 = Factory.insert(:template)
    t2 = Factory.insert(:template)
    t3 = Factory.insert(:template)

    encoded_sequence = Jason.encode!([to_string(t3.id), to_string(t2.id), to_string(t1.id)])

    conn =
      VillainController.sequence_templates(conn, %{
        "sequence" => encoded_sequence
      })

    resp_map = Jason.decode!(conn.resp_body)
    assert resp_map["status"] == 200
  end
end
