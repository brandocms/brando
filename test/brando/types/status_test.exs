defmodule Brando.Types.StatusTest do
  use ExUnit.Case
  alias Brando.Type.Status

  test "cast" do
    assert Status.cast(:atom) == {:ok, :atom}
    assert Status.cast("0") == {:ok, :draft}
    assert Status.cast(0) == {:ok, :draft}
  end

  test "blank?" do
    assert Status.blank?(:atom) == false
  end

  test "load" do
    assert Status.load(0) == {:ok, :draft}
    assert Status.load(1) == {:ok, :published}
  end

  test "dump" do
    assert Status.dump(:draft) == {:ok, 0}
    assert Status.dump("0") == {:ok, 0}
    assert Status.dump(5) == {:ok, 5}
  end
end