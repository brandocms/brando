defmodule BrandoAdmin.Components.Form.Input.OptionsTest do
  # Phase 3 / E4 in the form audit. The `:languages` / `:admin_languages`
  # expansion existed as three byte-identical `case` arms in `Input.radios/1`,
  # `Input.Select` and `Input.MultiSelect`.
  # `async: false`: the memoization test below mutates
  # `Application.put_env(:brando, :languages, ...)`, which is global. Nothing
  # reads it concurrently today, but an async test that did would see "Testish".
  use ExUnit.Case, async: false

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

  # `expand/1` is total so the three callers (`Input.radios/1`, `Input.Select`,
  # `Input.MultiSelect`) never name the tokens themselves — they pipe everything
  # through and pattern-match the result. That only works if a non-token comes
  # back byte-identical, so pin each shape a caller branches on.
  test "passes every non-token value through untouched" do
    options_fun = fn _form, _opts -> [] end
    list = [%{label: "One", value: "1"}]

    assert Options.expand(nil) == nil
    assert Options.expand(options_fun) == options_fun
    assert Options.expand(list) == list
    assert Options.expand(:not_a_token) == :not_a_token
  end
end
