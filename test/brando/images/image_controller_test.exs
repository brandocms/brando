defmodule Brando.Image.ControllerTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase
  use Plug.Test
  use RouterHelper

  alias Brando.Image
  alias Brando.Type.ImageConfig
  alias Brando.Factory

  @path "#{Path.expand("../../", __DIR__)}/fixtures/sample.png"
  @series_params %{"name" => "Series name", "slug" => "series-name",
                   "credits" => "Credits", "order" => 0}
  @category_params %{"cfg" => %ImageConfig{}, "name" => "Test Category",
                     "slug" => "test-category"}

  setup do
    user = Factory.insert(:user)
    category = Factory.insert(:image_category, creator: user)
    series = Factory.insert(:image_series, creator: user, image_category: category)
    {:ok, %{user: user, category: category, series: series}}
  end

  test "index" do
    conn =
      :get
      |> call("/admin/images/")
      |> with_user
      |> send_request

    assert html_response(conn, 200) =~ "Index"
    assert html_response(conn, 200) =~ "Test category"
    assert html_response(conn, 200) =~ "Series name"
  end

  test "set_properties", %{user: user, series: series} do
    up_params = Factory.build(:plug_upload)

    conn =
      :post
      |> call("/admin/images/series/#{series.id}/upload", %{"id" => series.id, "image" => up_params})
      |> with_user(user)
      |> as_json
      |> send_request

    assert json_response(conn, 200) == %{"status" => "200"}

    q = from(m in Image,
          where: m.image_series_id == ^series.id,
          order_by: m.sequence
        )

    image = q |> Brando.repo.all |> List.first

    refute image.image.credits
    refute image.image.title

    conn =
      :post
      |> call("/admin/images/set-properties",
              %{"id" => image.id, "form" => %{"credits" => "credits", "title" => "title"}})
      |> with_user(user)
      |> as_json
      |> send_request

    response = json_response(conn, 200)

    assert Map.get(response, "attrs") == %{"credits" => "credits", "title" => "title"}
    assert Map.get(response, "status") == "200"

    image = q |> Brando.repo.all |> List.first

    assert image.image.credits == "credits"
    assert image.image.title   == "title"
  end

  test "delete_selected", %{series: series, user: user} do
    q = from(m in Image,
      select: m.id,
      where: m.image_series_id == ^series.id,
      order_by: m.sequence
    )

    images = Brando.repo.all(q)

    conn =
      :post
      |> call("/admin/images/delete-selected-images", %{"ids" => images})
      |> with_user(user)
      |> as_json
      |> send_request

    assert json_response(conn, 200) == %{"status" => "200", "ids" => images}

    images = Brando.repo.all(q)

    assert images == []
  end
end
