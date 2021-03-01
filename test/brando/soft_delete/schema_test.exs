defmodule Brando.SoftDelete.SchemaTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use Brando.SoftDelete.Schema
  end

  test "has __soft_delete__" do
    assert Brando.SoftDelete.is_soft_deletable(__MODULE__.Schema)
    assert __MODULE__.Schema.__soft_delete__() == true
  end
end
