defmodule Brando.I18nSingleLanguageTest do
  # Changes the global :languages config.
  use ExUnit.Case, async: false

  import Brando.Test.Support, only: [put_test_env: 2]

  test "single_language?/1 is true when there's one content language to pick" do
    put_test_env(:languages, [[value: "en", text: "English"]])
    assert Brando.I18n.single_language?(nil)

    put_test_env(:languages, [[value: "en", text: "English"], [value: "no", text: "Norsk"]])
    refute Brando.I18n.single_language?(nil)
  end
end
