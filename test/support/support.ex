defmodule Brando.Test.Support do
  @moduledoc false
  import ExUnit.Assertions

  def assert_attr(target, attr, value) do
    assert Floki.attribute(target, attr) == value
    target
  end

  @doc """
  Sets `Application.put_env(:brando, key, value)` for one test and restores it
  properly afterwards.

  "Properly" is the whole reason this exists. The obvious restore —

      original = Application.get_env(:brando, key)
      on_exit(fn -> Application.put_env(:brando, key, original) end)

  — stores `nil` when the key was absent, and `nil` is **not** absent:
  `Application.get_env(:brando, key, [])` returns the stored `nil` in preference
  to its own default, so the next caller does `Keyword.get(nil, …)` and gets a
  `FunctionClauseError` instead of the behaviour it configured for. It leaks
  across files, so it surfaces as one test breaking another — which is how it
  was found, at the cost of a cross-file flake.

  `fetch_env/2` distinguishes "absent" from "present and nil", and `delete_env/2`
  is what restores the former.
  """
  def put_test_env(key, value) do
    original = Application.fetch_env(:brando, key)
    Application.put_env(:brando, key, value)

    ExUnit.Callbacks.on_exit(fn ->
      case original do
        {:ok, previous} -> Application.put_env(:brando, key, previous)
        :error -> Application.delete_env(:brando, key)
      end
    end)
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
