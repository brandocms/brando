defmodule Brando.Content.Identifier.RegistryTest do
  use ExUnit.Case

  alias Brando.Content.Identifier.Registry

  describe "list_persistent_identifier_modules/0" do
    test "returns list of modules with persistent identifiers" do
      modules = Registry.list_persistent_identifier_modules()
      assert is_list(modules)
    end
  end

  describe "list_persistent_identifier_modules/1" do
    test "returns list including Brando modules when passed :include_brando" do
      modules = Registry.list_persistent_identifier_modules(:include_brando)
      assert is_list(modules)
      # Should include Brando.Pages.Page
      assert Brando.Pages.Page in modules
    end
  end

  describe "has_persistent_identifier?/1" do
    test "returns true for Page schema" do
      assert Registry.has_persistent_identifier?(Brando.Pages.Page)
    end

    test "returns false for Var schema (persist_identifier false)" do
      refute Registry.has_persistent_identifier?(Brando.Content.Var)
    end

    test "returns false for Block schema (no identifier)" do
      refute Registry.has_persistent_identifier?(Brando.Content.Block)
    end
  end
end
