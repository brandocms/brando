defmodule E2eProjectWeb.ClientTest do
  use E2eProject.ModelCase

  alias E2eProjectWeb.Client

  @valid_attrs %{name: "some content", status: :published, language: "some content", inserted_at: "2010-04-17 14:00:00", updated_at: "2010-04-17 14:00:00", slug: "some content"}
  @invalid_attrs %{}

  test "changeset with valid attributes" do
    changeset = Client.changeset(%Client{}, @valid_attrs)
    assert changeset.valid?
  end

  test "changeset with invalid attributes" do
    changeset = Client.changeset(%Client{}, @invalid_attrs)
    refute changeset.valid?
  end
end
