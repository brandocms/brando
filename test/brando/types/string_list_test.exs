defmodule Brando.Type.StringListTest do
  use ExUnit.Case, async: true

  alias Brando.Type.StringList

  test "casts a list, trimming and dropping blanks" do
    assert StringList.cast([" Norway ", "", "Europe", nil]) == {:ok, ["Norway", "Europe"]}
  end

  test "casts the comma-separated string the field used to hold" do
    assert StringList.cast("Norway, Europe,, United States ") == {:ok, ["Norway", "Europe", "United States"]}
  end

  test "casts the indexed map a form submits, in index order" do
    assert StringList.cast(%{"1" => "b", "0" => "a", "2" => ""}) == {:ok, ["a", "b"]}
  end

  test "nil is an empty list" do
    assert StringList.cast(nil) == {:ok, []}
    assert StringList.dump(nil) == {:ok, []}
  end

  test "loads a legacy string as a list" do
    assert StringList.load("Oslo,Bergen") == {:ok, ["Oslo", "Bergen"]}
  end

  test "equality ignores whitespace and blanks" do
    assert StringList.equal?(["a", " b "], ["a", "b", ""])
  end

  test "round-trips through an embedded schema" do
    config = %Brando.Sites.Identity.TypeConfig{}
    changeset = Ecto.Changeset.cast(config, %{area_served: ["Norway", ""]}, [:area_served])
    assert Ecto.Changeset.get_field(changeset, :area_served) == ["Norway"]
  end
end
