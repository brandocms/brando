defmodule Brando.Types.RoleTest do
  use ExUnit.Case
  alias Brando.Type.Role

  test "cast" do
    assert Role.cast("superuser") == {:ok, :superuser}
    assert Role.cast(2) == {:ok, :admin}
  end

  test "load" do
    assert Role.load(0) == {:ok, :user}
  end

  test "dump" do
    assert Role.dump(:superuser) == {:ok, 3}
  end
end
