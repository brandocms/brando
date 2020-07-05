defmodule Brando.Integration.ImageSeriesTest do
  use ExUnit.Case, async: true
  use Brando.ConnCase
  use Brando.Integration.TestCase

  alias Brando.Factory
  alias Brando.ImageSeries

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

  test "by_category_id", %{category: category} do
    q = ImageSeries.by_category_id(category.id)
    result = Brando.repo().all(q)
    assert length(result) == 1
    series = List.first(result)
    assert series.name == "Series name"
  end

  test "validate_paths", %{series: series} do
    cs = ImageSeries.changeset(series, %{slug: "abracadabra"})
    assert Ecto.Changeset.get_change(cs, :slug) == "abracadabra"
    cs = ImageSeries.validate_paths(cs)

    assert Ecto.Changeset.get_change(cs, :cfg).upload_path ==
             "portfolio/test-category/abracadabra"
  end
end
