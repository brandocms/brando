defmodule Brando.Test do
  @moduledoc """
  Test helpers for Brando projects.

  Add `use Brando.Test` to your `DataCase` and `ConnCase` (inside `using`).
  It imports these helpers and `Brando.AI.Cassette.use_cassette/3`, and lets
  a test tag pick a cassette with `@tag cassette: "name"`.

  See the testing guide for setting up a project.
  """

  defmacro __using__(_opts) do
    quote do
      import Brando.Test
      import Brando.AI.Cassette, only: [use_cassette: 2, use_cassette: 3]

      setup {Brando.AI.Cassette, :setup_tags}
    end
  end
end
