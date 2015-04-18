defmodule Brando.Integration.ImageTest do
  use ExUnit.Case
  use Brando.Integration.TestCase
  alias Brando.User
  alias Brando.Image
  alias Brando.ImageSeries
  alias Brando.ImageCategory
  alias Brando.Type.Image.Config

  @params %{order: 0, image: %{title: "Title", credits: "credits",
                                       path: "/tmp/path/to/fake/image.jpg",
                                       sizes: %{small: "/tmp/path/to/fake/image.jpg", thumb: "/tmp/path/to/fake/thumb.jpg"}}}
  @params2 %{order: 1, image: %{title: "Title2", credits: "credits2",
                                       path: "/tmp/path/to/fake/image2.jpg",
                                       sizes: %{small: "/tmp/path/to/fake/image2.jpg", thumb: "/tmp/path/to/fake/thumb2.jpg"}}}
  @series_params %{name: "Series name", slug: "series-name", credits: "Credits", order: 0, creator_id: 1}
  @category_params %{cfg: %Config{}, creator_id: 1, name: "Test Category", slug: "test-category"}
  @user_params %{avatar: nil, role: ["2", "4"],
                 email: "fanogigyni@gmail.com", full_name: "Nita Bond",
                 password: "finimeze", status: "1", username: "zabuzasixu"}

  setup do
    {:ok, user} = User.create(@user_params)
    {:ok, category} =
      @category_params
      |> Map.put(:creator_id, user.id)
      |> ImageCategory.create(user)
    {:ok, series} =
      @series_params
      |> Map.put(:creator_id, user.id)
      |> Map.put(:image_category_id, category.id)
      |> ImageSeries.create(user)
    {:ok, %{user: user, category: category, series: series}}
  end

  test "create/2", %{user: user, series: series} do
    assert {:ok, image} =
      @params
      |> Map.put(:creator_id, user.id)
      |> Map.put(:image_series_id, series.id)
      |> Image.create(user)

    assert image.creator_id == user.id
    assert image.image_series_id == series.id
  end

  test "create/2 bad params", %{user: user} do
    assert {:error, errors} =
      @params |> Image.create(user)

    assert errors == [image_series_id: "can't be blank"]
  end

  test "update/2", %{user: user, series: series} do
    assert {:ok, image} =
      @params
      |> Map.put(:creator_id, user.id)
      |> Map.put(:image_series_id, series.id)
      |> Image.create(user)

    assert image.creator_id == user.id
    assert image.image_series_id == series.id
    assert image.order == 0

    assert {:ok, image} = image |> Image.update(%{"order" => 4})
    assert image.order == 4
  end

  test "update/2 bad params", %{user: user, series: series} do
    assert {:ok, image} =
      @params
      |> Map.put(:creator_id, user.id)
      |> Map.put(:image_series_id, series.id)
      |> Image.create(user)

    assert image.creator_id == user.id
    assert image.image_series_id == series.id
    assert image.order == 0

    assert {:error, errors} = image |> Image.update(%{"order" => "string"})
    assert errors == [order: :invalid]
  end

  test "get/1", %{user: user, series: series} do
    assert {:ok, image} =
      @params
      |> Map.put(:creator_id, user.id)
      |> Map.put(:image_series_id, series.id)
      |> Image.create(user)
    assert Image.get(id: image.id).id == image.id
    assert Image.get(id: image.id).creator_id == image.creator_id
    assert Image.get(id: 2000) == nil
  end

  test "get!/1", %{user: user, series: series} do
    assert {:ok, image} =
      @params
      |> Map.put(:creator_id, user.id)
      |> Map.put(:image_series_id, series.id)
      |> Image.create(user)
    assert Image.get!(id: image.id).id == image.id
    assert_raise Ecto.NoResultsError, fn ->
      Image.get!(id: 2000)
    end
  end

  test "reorder_images/2", %{user: user, series: series} do
    assert {:ok, image1} =
      @params
      |> Map.put(:creator_id, user.id)
      |> Map.put(:image_series_id, series.id)
      |> Image.create(user)
    assert {:ok, image2} =
      @params2
      |> Map.put(:creator_id, user.id)
      |> Map.put(:image_series_id, series.id)
      |> Image.create(user)

    assert image1.order == 0
    assert image2.order == 1

    assert {:ok, _} = Image.reorder_images([to_string(image1.id), to_string(image2.id)], [1, 0])

    image1 = Image.get!(id: image1.id)
    image2 = Image.get!(id: image2.id)
    assert image1.order == 1
    assert image2.order == 0
  end

  test "delete/1", %{user: user, series: series} do
    assert {:ok, image} =
      @params
      |> Map.put(:creator_id, user.id)
      |> Map.put(:image_series_id, series.id)
      |> Image.create(user)
    assert Image.get!(id: image.id).id == image.id
    assert Image.delete(image)
    refute Image.get(id: image.id)

    assert {:ok, image} =
      @params
      |> Map.put(:creator_id, user.id)
      |> Map.put(:image_series_id, series.id)
      |> Image.create(user)
    assert Image.get!(id: image.id).id == image.id
    assert Image.delete(image.id)
    refute Image.get(id: image.id)

    assert {:ok, image1} =
      @params
      |> Map.put(:creator_id, user.id)
      |> Map.put(:image_series_id, series.id)
      |> Image.create(user)
    assert {:ok, image2} =
      @params2
      |> Map.put(:creator_id, user.id)
      |> Map.put(:image_series_id, series.id)
      |> Image.create(user)
    assert Image.get!(id: image1.id).id == image1.id
    assert Image.get!(id: image2.id).id == image2.id
    assert Image.delete([image1.id, image2.id])
    refute Image.get(id: image1.id)
    refute Image.get(id: image2.id)
  end

  test "delete_dependent_images/1", %{user: user, series: series} do
    assert {:ok, image} =
      @params
      |> Map.put(:creator_id, user.id)
      |> Map.put(:image_series_id, series.id)
      |> Image.create(user)
    assert Image.get!(id: image.id).id == image.id

    assert {:ok, image} =
      @params
      |> Map.put(:creator_id, user.id)
      |> Map.put(:image_series_id, series.id)
      |> Image.create(user)
    assert Image.get!(id: image.id).id == image.id

    series =
      [id: series.id]
      |> ImageSeries.get!
      |> Brando.get_repo.preload(:images)

    assert Enum.count(series.images) == 2
    Image.delete_dependent_images(series.id)

    series =
      [id: series.id]
      |> ImageSeries.get!
      |> Brando.get_repo.preload(:images)

    assert Enum.count(series.images) == 0
  end

  # test "all/0" do
  #   assert Image.all == []
  #   assert {:ok, _user} = Image.create(@params)
  #   refute Image.all == []
  # end

  # test "auth?/2" do
  #   assert {:ok, user} = Image.create(@params)
  #   assert Image.auth?(user, "finimeze")
  #   refute Image.auth?(user, "finimeze123")
  # end

  # test "set_last_login/1" do
  #   assert {:ok, user} = Image.create(@params)
  #   new_user = Image.set_last_login(user)
  #   refute user.last_login == new_user.last_login
  # end

  # test "has_role?/1" do
  #   assert {:ok, user} = Image.create(@params)
  #   assert Image.has_role?(user, :superuser)
  #   assert Image.has_role?(user, :admin)
  #   refute Image.has_role?(user, :staff)
  # end

  # test "check_for_uploads/2 success" do
  #   assert {:ok, user} = Image.create(@params)
  #   up_plug =
  #     %Plug.Upload{content_type: "image/png",
  #                  filename: "sample.png",
  #                  path: "#{Path.expand("../../../", __DIR__)}/fixtures/sample.png"}
  #   up_params = Dict.put(%{}, "avatar", up_plug)
  #   assert {:ok, dict} = Image.check_for_uploads(user, up_params)
  #   user = Image.get(email: "fanogigyni@gmail.com")
  #   assert user.avatar == dict.avatar
  #   assert File.exists?(Path.join([Brando.Images.Utils.get_media_abspath, dict.avatar.path]))
  #   Image.delete(user)
  #   refute File.exists?(Path.join([Brando.Images.Utils.get_media_abspath, dict.avatar.path]))
  # end

  # test "check_for_uploads/2 error" do
  #   assert {:ok, user} = Image.create(@params)
  #   up_plug =
  #     %Plug.Upload{content_type: "image/png",
  #                  filename: "",
  #                  path: "#{Path.expand("../../../", __DIR__)}/fixtures/sample.png"}
  #   up_params = Dict.put(@params, "avatar", up_plug)
  #   assert_raise Brando.Exception.UploadError, "Blankt filnavn!", fn ->
  #     Image.check_for_uploads(user, up_params)
  #   end
  # end

  # test "check_for_uploads/2 format error" do
  #   assert {:ok, user} = Image.create(@params)
  #   up_plug =
  #     %Plug.Upload{content_type: "image/gif",
  #                  filename: "sample.gif",
  #                  path: "#{Path.expand("../../../", __DIR__)}/fixtures/sample.png"}
  #   up_params = Dict.put(@params, "avatar", up_plug)
  #   assert_raise Brando.Exception.UploadError, fn -> Image.check_for_uploads(user, up_params) end
  # end

  # test "check_for_uploads/2 copy error" do
  #   assert {:ok, user} = Image.create(@params)
  #   up_plug =
  #     %Plug.Upload{content_type: "image/png",
  #                  filename: "sample.png",
  #                  path: "#{Path.expand("../../../", __DIR__)}/fixtures/non_existant.png"}
  #   up_params = Dict.put(@params, "avatar", up_plug)
  #   assert_raise Brando.Exception.UploadError, "Feil under kopiering -> enoent", fn ->
  #     Image.check_for_uploads(user, up_params)
  #   end
  # end

  # test "check_for_uploads/2 noupload" do
  #   assert {:ok, user} = Image.create(@params)
  #   assert [] = Image.check_for_uploads(user, @params)
  # end
end