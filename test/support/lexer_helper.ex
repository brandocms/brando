defmodule Brando.LexerHelper do
  @moduledoc false

  import ExUnit.Assertions

  def assert_parse(doc, match) do
    assert {:ok, ^match, "", _, _, _} = Brando.Lexer.parse(doc)
  end
end
