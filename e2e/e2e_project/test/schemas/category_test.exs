defmodule E2eProjectWeb.CategoryTest do
  use E2eProject.ModelCase

  alias E2eProjectWeb.Category

  @valid_attrs %{status: :published, title: "some content", language: "some content", slug: "some content", inserted_at: "2010-04-17 14:00:00", updated_at: "2010-04-17 14:00:00", sequence: 42}
  @invalid_attrs %{}

  test "changeset with valid attributes" do
    changeset = Category.changeset(%Category{}, @valid_attrs)
    assert changeset.valid?
  end

  test "changeset with invalid attributes" do
    changeset = Category.changeset(%Category{}, @invalid_attrs)
    refute changeset.valid?
  end
end
