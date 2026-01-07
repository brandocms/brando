defmodule Brando.Test.Support do
  @moduledoc false
  import ExUnit.Assertions

  def assert_attr(target, attr, value) do
    assert Floki.attribute(target, attr) == value
    target
  end

  @doc """
  Recursively strips __spark_metadata__ from structs for comparison in tests.

  This is necessary because Spark DSL populates __spark_metadata__ with
  environment-specific file paths that would cause test failures in CI
  or on different developer machines.
  """
  def strip_spark_metadata(struct) when is_struct(struct) do
    struct
    |> Map.from_struct()
    |> Map.delete(:__spark_metadata__)
    |> Enum.map(fn {k, v} -> {k, strip_spark_metadata(v)} end)
    |> Map.new()
    |> then(&struct(struct.__struct__, &1))
  end

  def strip_spark_metadata(list) when is_list(list) do
    Enum.map(list, &strip_spark_metadata/1)
  end

  def strip_spark_metadata(map) when is_map(map) do
    map
    |> Map.delete(:__spark_metadata__)
    |> Enum.map(fn {k, v} -> {k, strip_spark_metadata(v)} end)
    |> Map.new()
  end

  def strip_spark_metadata(other), do: other
end
