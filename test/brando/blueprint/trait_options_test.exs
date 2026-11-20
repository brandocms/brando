defmodule Brando.Blueprint.TraitOptionsTest do
  # A trait's options as the Blueprint DSL compiles them into `__trait__/1`,
  # values that are not literals in quoted code included (#3752)
  use ExUnit.Case, async: true

  alias Brando.SyncSelectorTest.Article

  test "a module selector in source_controlled_fields compiles and is read back" do
    assert Article.__trait__(Brando.Trait.Translatable)[:source_controlled_fields] ==
             [:year, {:module, "hero-banner", [:layout]}]

    assert %{
             source_controlled_fields: [:year],
             source_controlled_module_vars: %{"hero-banner" => ["layout"]}
           } = Article.__translatable_config__()
  end
end
