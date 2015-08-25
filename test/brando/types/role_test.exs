defmodule Brando.Types.RoleTest do
  use ExUnit.Case
  alias Brando.Type.Role

  test "cast" do
    assert Role.cast(["2", "4"]) == {:ok, [:superuser, :admin]}
    assert Role.cast([2, 4]) == {:ok, [:superuser, :admin]}
    assert Role.cast([:superuser, :admin]) == {:ok, [:superuser, :admin]}
    assert Role.cast("0") == {:ok, 0}
    assert Role.cast(:test) == :error
  end

  test "blank?" do
    refute Role.blank?([2, 4])
  end

  test "load" do
    assert Role.load(6) == {:ok, [:superuser, :admin]}
    assert Role.load(0) == {:ok, []}
  end

  test "dump" do
    assert Role.dump(6) == {:ok, 6}
    assert Role.dump("6") == {:ok, 6}
    assert Role.dump(["2", "4"]) == {:ok, 6}
    assert Role.dump([2, 4]) == {:ok, 6}
    assert Role.dump([:superuser, :admin]) == {:ok, 6}
  end
end