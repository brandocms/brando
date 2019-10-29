defmodule Mix.BrandoTest do
  use ExUnit.Case, async: true

  test "check_module_name_availability" do
    assert Mix.Brando.check_module_name_availability(Mix.BrandoTest) ==
             {:error, "Module name Mix.BrandoTest is already taken, please choose another name"}
  end

  test "base" do
    assert Mix.Brando.base() == "Brando"
  end

  test "modules" do
    modules = Mix.Brando.modules()

    if modules != [] do
      assert Brando.Image in Mix.Brando.modules()
    end
  end
end
