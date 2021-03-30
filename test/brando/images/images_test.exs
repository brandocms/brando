defmodule Brando.ImagesTest do
  use ExUnit.Case
  use Brando.ConnCase

  alias Brando.Factory
  alias Brando.Images

  test "create_image" do
    user = Factory.insert(:random_user)
    assert {:ok, _} = Images.create_image(Factory.params_for(:image), user)
  end

  test "update_image" do
    user = Factory.insert(:random_user)
    img = Factory.insert(:image)
    assert {:ok, img} = Images.update_image(img, %{sequence: 99}, user)
    assert img.sequence == 99
  end

  test "get_image" do
    img = Factory.insert(:image)
    {:ok, img2} = Images.get_image(%{matches: [id: img.id]})
    assert img == img2
  end

  test "get_image!" do
    img = Factory.insert(:image)
    assert img2 = Images.get_image!(img.id)
    assert img == img2
  end

  test "update_image_meta" do
    user = Factory.insert(:random_user)
    img = Factory.insert(:image, image_series: Factory.build(:image_series))
    fixture = Path.join([Path.expand("../../", __DIR__), "fixtures", "sample.jpg"])
    target = Path.join([Images.Utils.media_path(img.image.path)])
    File.mkdir_p!(Path.dirname(target))

    File.cp_r!(
      fixture,
      target
    )

    assert {:ok, img2} = Images.update_image_meta(img, %{focal: %{x: 0, y: 0}}, user)
    assert img2.image.focal == %{x: 0, y: 0}

    assert {:ok, img3} = Images.update_image_meta(img, %{title: "Hello!"}, user)
    assert img3.image.title == "Hello!"
  end

  test "get_category_id_by_slug" do
    c1 = Factory.insert(:image_category)
    assert {:ok, c1_id} = Images.get_category_id_by_slug(c1.slug)
    assert c1_id == c1.id
  end

  test "get_or_create_category_id_by_slug" do
    u1 = Factory.insert(:random_user)
    {:ok, c1} = Images.get_or_create_category_id_by_slug("wham-bam", u1)
    assert c1.slug == "wham-bam"
    {:ok, c2} = Images.get_or_create_category_id_by_slug("wham-bam", u1)
    assert c2.slug == c1.slug
  end

  test "delete_images" do
    i1 = Factory.insert(:image)
    i2 = Factory.insert(:image)

    assert {2, nil} = Images.delete_images([i1.id, i2.id])
  end

  test "create_series" do
    u1 = Factory.insert(:random_user)
    c1 = Factory.insert(:image_category)

    {:ok, s1} =
      Images.create_series(
        Factory.params_for(:image_series, image_category_id: c1.id),
        u1
      )

    assert s1.slug == "series-name"
  end

  test "update_series" do
    s1 = Factory.insert(:image_series, image_category: Factory.build(:image_category))
    {:ok, s2} = Images.update_series(s1.id, %{slug: "new-name"})
    assert s2.slug == "new-name"
  end

  test "update_series_config" do
    s1 = Factory.insert(:image_series, image_category: Factory.build(:image_category))
    {:ok, s2} = Images.update_series_config(s1.id, %{random_filename: true})
    assert s2.cfg.random_filename == true
  end

  test "delete_series" do
    s1 = Factory.insert(:image_series, image_category: Factory.build(:image_category))
    {:ok, s2} = Images.delete_series(s1.id)
    refute s2.deleted_at == nil
  end

  test "create_category" do
    u1 = Factory.insert(:random_user)
    {:ok, c1} = Images.create_category(Factory.params_for(:image_category), u1)
    assert c1.slug == "test-category"
  end

  test "update_category" do
    c1 = Factory.insert(:image_category)
    s1 = Factory.insert(:image_series, image_category: c1)
    _ = Factory.insert(:image, image_series_id: s1.id)

    {:propagate, c2} = Images.update_category(c1.id, %{slug: "new-name"})
    assert c2.slug == "new-name"

    {:ok, c2} = Images.update_category(c1.id, %{cfg: %{random_filename: true}})
    assert c2.cfg.random_filename == true
  end

  test "get_category" do
    c1 = Factory.insert(:image_category)
    assert {:ok, c2} = Brando.Images.get_image_category(%{matches: [id: c1.id]})
    assert c2.id == c1.id
  end

  test "get_category_by_slug" do
    c1 = Factory.insert(:image_category)
    assert {:ok, c2} = Images.get_category_by_slug(c1.slug)
    assert c2.id == c1.id
  end

  test "get_category_config" do
    c1 = Factory.insert(:image_category)
    assert {:ok, cfg} = Images.get_category_config(c1.id)
    assert cfg == c1.cfg
  end

  test "get_category_config_by_slug" do
    c1 = Factory.insert(:image_category)
    assert {:ok, cfg} = Images.get_category_config_by_slug(c1.slug)
    assert cfg == c1.cfg
  end

  test "get_series_by_slug" do
    s1 = Factory.insert(:image_series)
    assert {:ok, s2} = Images.get_series_by_slug(s1.slug)
    assert s2.id == s1.id
  end

  test "get_series_config" do
    assert {:error, _} = Images.get_series_config(5_299_345_348)
  end

  test "list_categories" do
    _c1 = Factory.insert(:image_category)
    assert {:ok, cats} = Images.list_categories()
    assert Enum.count(cats) == 1
  end

  test "update_category_config" do
    c1 = Factory.insert(:image_category)
    {:ok, c2} = Images.update_category_config(c1.id, %{random_filename: true})
    assert c2.cfg.random_filename == true
  end

  test "propagate_category_config" do
    c1 = Factory.insert(:image_category)
    s1 = Factory.insert(:image_series, image_category: c1)
    _s2 = Factory.insert(:image_series, image_category: c1)
    _i1 = Factory.insert(:image, image_series_id: s1.id)

    count =
      Images.propagate_category_config(c1.id)
      |> Keyword.keys()
      |> Enum.count()

    assert count == 2
  end

  test "delete_category" do
    c1 = Factory.insert(:image_category)
    s1 = Factory.insert(:image_series, image_category: c1)
    _s2 = Factory.insert(:image_series, image_category: c1)
    _i1 = Factory.insert(:image, image_series_id: s1.id)

    {:ok, c2} = Images.delete_category(c1.id)
    refute c2.deleted_at == nil
  end

  test "duplicate_category" do
    u1 = Factory.insert(:random_user)
    c1 = Factory.insert(:image_category)

    {:ok, c2} = Images.duplicate_category(c1.id, u1)

    assert c2.name == "Test Category kopi"
    assert c2.slug == "test-category-kopi"
    refute c1.id == c2.id
  end

  test "count_image_series" do
    c1 = Factory.insert(:image_category)
    _s1 = Factory.insert(:image_series, image_category: c1)
    _s2 = Factory.insert(:image_series, image_category: c1)

    assert Images.count_image_series(c1.id) == 2
  end

  test "get_all_orphaned_series" do
    assert Images.get_all_orphaned_series() == []

    c1 = Factory.insert(:image_category)
    s1 = Factory.insert(:image_series, image_category: c1)
    s2 = Factory.insert(:image_series, image_category: c1)
    i1 = Factory.insert(:image, image_series: s1)

    fixture = Path.join([Path.expand("../../", __DIR__), "fixtures", "sample.jpg"])
    target = Path.join([Images.Utils.media_path(i1.image.path)])
    File.mkdir_p!(Path.dirname(target))

    File.cp_r!(
      fixture,
      target
    )

    Images.delete_series(s1.id)
    Images.delete_series(s2.id)

    assert Images.get_all_orphaned_series() == []
  end
end
