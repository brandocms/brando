defmodule Mix.BrandoTest do
  use ExUnit.Case, async: true

  test "check_module_name_availability" do
    assert_raise Mix.Error, fn ->
      Mix.Brando.check_module_name_availability!(Mix.BrandoTest)
    end
  end

  test "base" do
    assert Mix.Brando.base() == "Brando"
  end

  test "modules" do
    assert Brando.Image in Mix.Brando.modules()
  end
end
