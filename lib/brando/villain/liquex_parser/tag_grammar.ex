defmodule Brando.Villain.LiquexParser.TagGrammar do
  @moduledoc false

  # Existing tag modules expose parse/0 as public API. Resolve the centralized
  # grammar dynamically so those rendering modules do not become dependencies
  # of the generated parser again through a static reverse edge.
  @syntax_module Module.concat(["Brando", "Villain", "LiquexParser", "Syntax"])

  @doc false
  @spec parse(atom()) :: NimbleParsec.t()
  def parse(tag), do: apply(@syntax_module, tag, [])
end
