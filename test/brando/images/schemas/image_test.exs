defmodule Brando.Integration.ImageTest do
  use ExUnit.Case
  use Brando.ConnCase
  use Brando.Integration.TestCase

  alias Brando.Factory
  alias Brando.Image
  alias Brando.Images
  alias Brando.ImageSeries

  @params %{
    "sequence" => 0,
    "image" => %Brando.Type.Image{
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
    "sequence" => 1,
    "image" => %Brando.Type.Image{
      title: "Title2",
      credits: "credits2",
      path: "/tmp/path/to/fake/image2.jpg",
      sizes: %{
        small: "/tmp/path/to/fake/image2.jpg",
        thumb: "/tmp/path/to/fake/thumb2.jpg"
      }
    }
  }

  setup_all do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Brando.repo())
    # we are setting :auto here so that the data persists for all tests,
    # normally (with :shared mode) every process runs in a transaction
    # and rolls back when it exits. setup_all runs in a distinct process
    # from each test so the data doesn't exist for each test.
    Ecto.Adapters.SQL.Sandbox.mode(Brando.repo(), :auto)
    user = Factory.insert(:random_user)
    category = Factory.insert(:image_category, creator: user)
    series = Factory.insert(:image_series, creator: user, image_category: category)

    on_exit(fn ->
      # this callback needs to checkout its own connection since it
      # runs in its own process
      :ok = Ecto.Adapters.SQL.Sandbox.checkout(Brando.repo())
      Ecto.Adapters.SQL.Sandbox.mode(Brando.repo(), :auto)

      Brando.repo().delete(series)
      Brando.repo().delete(category)
      Brando.repo().delete(user)
      :ok
    end)

    {:ok, %{user: user, category: category, series: series}}
  end

  test "create/2", %{user: user, series: series} do
    assert {:ok, image} =
             @params
             |> Map.put("creator_id", user.id)
             |> Map.put("image_series_id", series.id)
             |> Images.create_image(user)

    assert image.creator_id == user.id
    assert image.image_series_id == series.id
  end

  test "create/2 bad params", %{user: user} do
    assert {:error, cs} = Images.create_image(%{}, user)
    assert cs.errors == [image: {"can't be blank", [validation: :required]}]
  end

  test "update/2", %{user: user, series: series} do
    assert {:ok, image} =
             @params
             |> Map.put("creator_id", user.id)
             |> Map.put("image_series_id", series.id)
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
             |> Map.put("creator_id", user.id)
             |> Map.put("image_series_id", series.id)
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
             |> Map.put("creator_id", user.id)
             |> Map.put("image_series_id", series.id)
             |> Images.create_image(user)

    assert image.image.title == "Title"
    assert image.image.credits == "credits"

    assert {:ok, new_image} =
             Images.update_image_meta(image, %{title: "new title", credits: "new credits"})

    refute new_image.image == image.image
    assert new_image.image.title == "new title"
    assert new_image.image.credits == "new credits"
  end

  test "get/1", %{user: user, series: series} do
    assert {:ok, image} =
             @params
             |> Map.put("creator_id", user.id)
             |> Map.put("image_series_id", series.id)
             |> Images.create_image(user)

    assert Brando.repo().get_by!(Image, id: image.id).id == image.id
    assert Brando.repo().get_by!(Image, id: image.id).creator_id == image.creator_id
    assert_raise Ecto.NoResultsError, fn -> Brando.repo().get_by!(Image, id: 1234) end
  end

  test "get!/1", %{user: user, series: series} do
    assert {:ok, image} =
             @params
             |> Map.put("creator_id", user.id)
             |> Map.put("image_series_id", series.id)
             |> Images.create_image(user)

    assert Brando.repo().get_by!(Image, id: image.id).id == image.id
    assert_raise Ecto.NoResultsError, fn -> Brando.repo().get_by!(Image, id: 1234) end
  end

  test "sequence/2", %{user: user, series: series} do
    assert {:ok, image1} =
             @params
             |> Map.put("creator_id", user.id)
             |> Map.put("image_series_id", series.id)
             |> Images.create_image(user)

    assert {:ok, image2} =
             @params2
             |> Map.put("creator_id", user.id)
             |> Map.put("image_series_id", series.id)
             |> Images.create_image(user)

    assert image1.sequence == 0
    assert image2.sequence == 1

    assert {:ok, _} = Image.sequence(%{"ids" => [image2.id, image1.id]})

    image1 = Brando.repo().get_by!(Image, id: image1.id)
    image2 = Brando.repo().get_by!(Image, id: image2.id)

    assert image1.sequence == 1
    assert image2.sequence == 0
  end

  test "delete_images_for/1", %{user: user, series: series} do
    assert {:ok, image} =
             @params
             |> Map.put("creator_id", user.id)
             |> Map.put("image_series_id", series.id)
             |> Images.create_image(user)

    assert Brando.repo().get_by!(Image, id: image.id).id == image.id

    assert {:ok, image} =
             @params
             |> Map.put("creator_id", user.id)
             |> Map.put("image_series_id", series.id)
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

    assert Enum.count(Enum.filter(series.images, &(&1.deleted_at != nil))) == 2
  end
end
