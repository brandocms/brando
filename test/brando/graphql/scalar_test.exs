defmodule Brando.ScalarTest do
  use ExUnit.Case
  alias Absinthe.Type

  defmodule TestSchema do
    use Absinthe.Schema
    use Brando.Schema

    import_types Absinthe.Plug.Types
    import_types Brando.Schema.Types

    query do
      # Query type must exist
    end
  end

  defp serialize(type, value) do
    TestSchema.__absinthe_type__(type)
    |> Type.Scalar.serialize(value)
  end

  defp parse(type, value) do
    TestSchema.__absinthe_type__(type)
    |> Type.Scalar.parse(value)
  end

  describe ":date" do
    test "parse" do
      assert {:ok, ~N[2012-07-06 00:00:00]} == parse(:date, %{value: "2012-07-06"})
    end

    test "serialize" do
      assert "2012-07-06" == serialize(:date, ~N[2012-07-06 00:00:00])
    end
  end

  describe ":time" do
    test "parse" do
      assert {:ok, ~U[2012-07-06 10:10:10.000000Z]} ==
               parse(:time, %{value: "2012-07-06 10:10:10.000000Z"})
    end

    test "serialize" do
      assert "2012-07-06T10:10:10.000000Z" == serialize(:time, ~U[2012-07-06 10:10:10.000000Z])
    end
  end

  describe ":atom" do
    test "parse" do
      assert {:ok, :test} == parse(:atom, %{value: "test"})
      assert {:ok, :test} == parse(:atom, %{value: :test})
    end

    test "serialize" do
      assert {:ok, :test} == serialize(:atom, "test")
      assert {:ok, :test} == serialize(:atom, :test)
    end
  end

  describe ":list" do
    test "parse" do
      assert {:ok, [1, 2, 3]} ==
               parse(:list, %{
                 fields: [
                   %{input_value: %{normalized: %{value: 1}}},
                   %{input_value: %{normalized: %{value: 2}}},
                   %{input_value: %{normalized: %{value: 3}}}
                 ]
               })
    end
  end

  describe ":order" do
    test "parse" do
      assert {:ok, [{:asc, :inserted_at}, {:desc, :sequence}]} ==
               parse(:order, %{value: "asc inserted_at, desc sequence"})
    end
  end

  describe ":json" do
    test "parse" do
      assert {:ok, %{"another" => %{"test" => "value2"}, "test" => "value"}} ==
               parse(:json, %Absinthe.Blueprint.Input.String{
                 value: "{\"another\":{\"test\":\"value2\"},\"test\":\"value\"}"
               })
    end

    test "serialize" do
      assert %{"another" => %{"test" => "value2"}, "test" => "value"} ==
               serialize(:json, %{"test" => "value", "another" => %{"test" => "value2"}})
    end
  end
end
