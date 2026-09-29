defmodule Brando.Content.ConfiguredModuleSetTest do
  # A site can give a block field of a schema it doesn't own (Brando's Page)
  # a module set in config; the form's own `module_set:` still wins.
  use ExUnit.Case, async: false

  alias Brando.Content.Proposals

  setup do
    previous = Application.get_env(:brando, Brando.Pages.Page)
    on_exit(fn -> Application.put_env(:brando, Brando.Pages.Page, previous || []) end)
  end

  test "the configured set applies to the field it names" do
    Application.put_env(:brando, Brando.Pages.Page, module_sets: [blocks: "Side"])

    assert Proposals.configured_module_set(Brando.Pages.Page, "blocks") == "Side"
    assert Proposals.configured_module_set(Brando.Pages.Page, :blocks) == "Side"
    assert Proposals.module_set(Brando.Pages.Page, "blocks") == "Side"
    assert Proposals.configured_module_set(Brando.Pages.Page, "other_blocks") == nil
  end

  test "without config there is no set" do
    Application.put_env(:brando, Brando.Pages.Page, [])
    assert Proposals.module_set(Brando.Pages.Page, "blocks") == nil
  end
end
