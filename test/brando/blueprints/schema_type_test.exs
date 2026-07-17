defmodule Brando.Blueprint.SchemaTypeTest do
  use ExUnit.Case, async: true

  test "Blueprint schemas export a standard struct type" do
    assert {:ok, types} = Code.Typespec.fetch_types(Brando.Files.File)
    assert {:type, {:t, type, []}} = Enum.find(types, &match?({:type, {:t, _, []}}, &1))
    assert {:type, _, :map, fields} = type

    assert Enum.any?(fields, fn field ->
             match?(
               {:type, _, :map_field_exact, [{:atom, _, :__struct__}, {:atom, _, Brando.Files.File}]},
               field
             )
           end)
  end

  test "application-defined t/0 types remain available" do
    assert {:ok, types} = Code.Typespec.fetch_types(Brando.Pages.Page)

    assert {:type, {:t, {:type, _, :map, _fields}, []}} =
             Enum.find(types, &match?({:type, {:t, _, []}}, &1))
  end
end
