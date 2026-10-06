defmodule Brando.Villain.ParserOverridableTest do
  use ExUnit.Case, async: true

  defmodule Parser do
    @moduledoc false
    use Brando.Villain.Parser
  end

  # `mix brando.migrate55` warns about site overrides that are not in this
  # list, so it must name exactly what `use Brando.Villain.Parser` defines.
  test "overridable_callbacks/0 lists every function the parser defines" do
    defined = Parser.__info__(:functions) -- [behaviour_info: 1]
    assert Enum.sort(defined) == Enum.sort(Brando.Villain.Parser.overridable_callbacks())
  end
end
