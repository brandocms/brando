defmodule Brando.Integration.ImageTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase

  alias Brando.Factory
  alias Brando.Image
  alias Brando.Images
  alias Brando.ImageSeries

  @params %{
    sequence: 0,
    image: %Brando.Type.Image{
      title: "Title",
      credits: "credits",
      path: "/tmp/path/to/fake/image.jpg",
      sizes: %{
        small: "/tmp/path/to/fake/image.jpg",
        thumb: "/tmp/path/to/fake/thumb.jpg"
      }
    }
  }

  @params2 %{
    sequence: 1,
    image: %Brando.Type.Image{
      title: "Title2",
      credits: "credits2",
      path: "/tmp/path/to/fake/image2.jpg",
      sizes: %{
        small: "/tmp/path/to/fake/image2.jpg",
        thumb: "/tmp/path/to/fake/thumb2.jpg"
      }
    }
  }

  setup do
    user = Factory.insert(:user)
    category = Factory.insert(:image_category, creator: user)
    series = Factory.insert(:image_series, creator: user, image_category: category)
    {:ok, %{user: user, category: category, series: series}}
  end

  test "create/2", %{user: user, series: series} do
    assert {:ok, image} =
             @params
             |> Map.put(:creator_id, user.id)
             |> Map.put(:image_series_id, series.id)
             |> Images.create_image(user)

    assert image.creator_id == user.id
    assert image.image_series_id == series.id
  end

  test "create/2 bad params", %{user: user} do
    assert {:error, cs} = Images.create_image(@params, user)
    assert cs.errors == [image_series_id: {"can't be blank", [validation: :required]}]
  end

  test "update/2", %{user: user, series: series} do
    assert {:ok, image} =
             @params
             |> Map.put(:creator_id, user.id)
             |> Map.put(:image_series_id, series.id)
             |> Images.create_image(user)

    assert image.creator_id == user.id
    assert image.image_series_id == series.id
    assert image.sequence == 0

    assert {:ok, image} = Images.update_image(image, %{"sequence" => 4})
    assert image.sequence == 4
  end

  test "update/2 bad params", %{user: user, series: series} do
    assert {:ok, image} =
             @params
             |> Map.put(:creator_id, user.id)
             |> Map.put(:image_series_id, series.id)
             |> Images.create_image(user)

    assert image.creator_id == user.id
    assert image.image_series_id == series.id
    assert image.sequence == 0

    assert {:error, cs} = Images.update_image(image, %{"sequence" => "string"})
    assert cs.errors == [sequence: {"is invalid", [type: :integer, validation: :cast]}]
  end

  test "update_image_meta/4", %{user: user, series: series} do
    assert {:ok, image} =
             @params
             |> Map.put(:creator_id, user.id)
             |> Map.put(:image_series_id, series.id)
             |> Images.create_image(user)

    assert image.image.title == "Title"
    assert image.image.credits == "credits"

    assert {:ok, new_image} =
             Images.update_image_meta(image, "new title", "new credits", %{"x" => 50, "y" => 50})

    refute new_image.image == image.image
    assert new_image.image.title == "new title"
    assert new_image.image.credits == "new credits"
  end

  test "get/1", %{user: user, series: series} do
    assert {:ok, image} =
             @params
             |> Map.put(:creator_id, user.id)
             |> Map.put(:image_series_id, series.id)
             |> Images.create_image(user)

    assert Brando.repo().get_by!(Image, id: image.id).id == image.id
    assert Brando.repo().get_by!(Image, id: image.id).creator_id == image.creator_id
    assert_raise Ecto.NoResultsError, fn -> Brando.repo().get_by!(Image, id: 1234) end
  end

  test "get!/1", %{user: user, series: series} do
    assert {:ok, image} =
             @params
             |> Map.put(:creator_id, user.id)
             |> Map.put(:image_series_id, series.id)
             |> Images.create_image(user)

    assert Brando.repo().get_by!(Image, id: image.id).id == image.id
    assert_raise Ecto.NoResultsError, fn -> Brando.repo().get_by!(Image, id: 1234) end
  end

  test "sequence/2", %{user: user, series: series} do
    assert {:ok, image1} =
             @params
             |> Map.put(:creator_id, user.id)
             |> Map.put(:image_series_id, series.id)
             |> Images.create_image(user)

    assert {:ok, image2} =
             @params2
             |> Map.put(:creator_id, user.id)
             |> Map.put(:image_series_id, series.id)
             |> Images.create_image(user)

    assert image1.sequence == 0
    assert image2.sequence == 1

    assert {:ok, _} = Image.sequence([to_string(image1.id), to_string(image2.id)], [1, 0])

    image1 = Brando.repo().get_by!(Image, id: image1.id)
    image2 = Brando.repo().get_by!(Image, id: image2.id)
    assert image1.sequence == 1
    assert image2.sequence == 0
  end

  test "delete_images_for/1", %{user: user, series: series} do
    assert {:ok, image} =
             @params
             |> Map.put(:creator_id, user.id)
             |> Map.put(:image_series_id, series.id)
             |> Images.create_image(user)

    assert Brando.repo().get_by!(Image, id: image.id).id == image.id

    assert {:ok, image} =
             @params
             |> Map.put(:creator_id, user.id)
             |> Map.put(:image_series_id, series.id)
             |> Images.create_image(user)

    assert Brando.repo().get_by!(Image, id: image.id).id == image.id

    series =
      ImageSeries
      |> Ecto.Query.preload([:images])
      |> Brando.repo().get_by!(id: series.id)
      |> Brando.repo().preload(:images)

    assert Enum.count(series.images) == 2
    :ok = Brando.Images.Utils.delete_images_for(:image_series, series.id)

    series =
      ImageSeries
      |> Ecto.Query.preload([:images])
      |> Brando.repo().get_by!(id: series.id)
      |> Brando.repo().preload(:images)

    assert Enum.count(series.images) == 0
  end

  test "meta", %{user: user, series: series} do
    assert {:ok, image} =
             @params
             |> Map.put(:creator_id, user.id)
             |> Map.put(:image_series_id, series.id)
             |> Images.create_image(user)

    assert Brando.Image.__name__(:singular) == "image"
    assert Brando.Image.__name__(:plural) == "images"
    assert Brando.Image.__repr__(image) == "#{image.id} | /tmp/path/to/fake/image.jpg"
  end
end
