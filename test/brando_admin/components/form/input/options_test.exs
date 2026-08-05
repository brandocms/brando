defmodule BrandoAdmin.Components.Form.Input.OptionsTest do
  # Phase 3 / E4 in the form audit. The `:languages` / `:admin_languages`
  # expansion existed as three byte-identical `case` arms in `Input.radios/1`,
  # `Input.Select` and `Input.MultiSelect`.
  use ExUnit.Case, async: true

  alias BrandoAdmin.Components.Form.Input.Options

  test "expands :languages into label/value maps" do
    expected =
      Enum.map(Brando.config(:languages), fn [{:value, value}, {:text, text}] ->
        %{label: text, value: value}
      end)

    assert Options.expand(:languages) == expected
    refute expected == []
  end

  test "expands :admin_languages the same way" do
    expected =
      Enum.map(Brando.config(:admin_languages), fn [{:value, value}, {:text, text}] ->
        %{label: text, value: value}
      end)

    assert Options.expand(:admin_languages) == expected
  end

  test "does not memoize — the language lists are runtime-configurable" do
    # `Brando.RuntimeConfig` can change these, so a cache here would go stale.
    # Pinned as a contract, not an implementation detail.
    previous = Brando.config(:languages)

    try do
      Application.put_env(:brando, :languages, [[value: "zz", text: "Testish"]])
      assert Options.expand(:languages) == [%{label: "Testish", value: "zz"}]
    after
      Application.put_env(:brando, :languages, previous)
    end

    assert Options.expand(:languages) == Options.expand(:languages)
  end

  test "tokens/0 lists exactly what expand/1 accepts" do
    assert Options.tokens() == [:languages, :admin_languages]
    for token <- Options.tokens(), do: assert(is_list(Options.expand(token)))
  end
end
