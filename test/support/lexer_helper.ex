defmodule Brando.Lexer.TestHelpers do
  @moduledoc false

  import ExUnit.Assertions

  @dialyzer {:nowarn_function, assert_parse: 2}
  def assert_parse(doc, match),
    do: assert({:ok, ^match, "", _, _, _} = Brando.Lexer.Parser.parse(doc))
end
