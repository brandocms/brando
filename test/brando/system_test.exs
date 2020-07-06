defmodule Brando.SystemTest do
  use ExUnit.Case
  use Brando.ConnCase

  test "system" do
    assert Brando.System.initialize() == :ok
  end
end
