defmodule E2eProjectWeb.ProjectTest do
  use E2eProject.ModelCase

  alias E2eProjectWeb.Project

  @valid_attrs %{status: :published, title: "some content", language: "some content", publish_at: "2010-04-17 14:00:00", slug: "some content", updated_at: "2010-04-17 14:00:00", deleted_at: "2010-04-17 14:00:00", inserted_at: "2010-04-17 14:00:00", sequence: 42, meta_description: "some content", meta_title: "some content", full_case: true, introduction: "some content"}
  @invalid_attrs %{}

  test "changeset with valid attributes" do
    changeset = Project.changeset(%Project{}, @valid_attrs)
    assert changeset.valid?
  end

  test "changeset with invalid attributes" do
    changeset = Project.changeset(%Project{}, @invalid_attrs)
    refute changeset.valid?
  end
end
