defmodule Brando.SoftDelete.SchemaTest do
  use ExUnit.Case, async: true

  defmodule Schema do
    use Brando.SoftDelete.Schema
  end

  test "has __soft_delete__" do
    assert {:__soft_delete__, 0} in __MODULE__.Schema.__info__(:functions)
    assert __MODULE__.Schema.__soft_delete__() == true
  end
end
