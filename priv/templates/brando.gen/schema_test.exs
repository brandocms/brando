defmodule <%= inspect schema_module %>Test do
  use ExUnit.Case, async: true

  test "rejects a missing <%= main_field %>" do
    changeset = <%= inspect schema_module %>.changeset(%<%= inspect schema_module %>{}, %{})
    assert Keyword.has_key?(changeset.errors, :<%= main_field %>)
  end
end
