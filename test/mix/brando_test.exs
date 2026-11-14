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
      assert Brando.Images.Image in Mix.Brando.modules()
    end
  end

  describe "yes_without_terminal/2" do
    test "accepts the diff when there is no terminal to ask on" do
      assert Mix.Brando.yes_without_terminal(["--contact"], false) == ["--contact", "--yes"]
    end

    test "asks on a terminal, and leaves an explicit choice or a dry run alone" do
      assert Mix.Brando.yes_without_terminal(["--contact"], true) == ["--contact"]
      assert Mix.Brando.yes_without_terminal(["--yes"], false) == ["--yes"]
      assert Mix.Brando.yes_without_terminal(["--no-yes"], false) == ["--no-yes"]
      assert Mix.Brando.yes_without_terminal(["--dry-run"], false) == ["--dry-run"]
    end
  end
end
