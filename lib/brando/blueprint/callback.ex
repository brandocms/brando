defmodule Brando.Blueprint.Callback do
  @moduledoc """
  Invokes callbacks stored by the Blueprint DSL.

  Blueprint callback options accept either anonymous functions or
  `{module, function, extra_args}` tuples. Runtime arguments are passed first,
  followed by the configured extra arguments.
  """

  @type t :: function() | {module(), atom(), [term()]}

  @doc """
  Invokes a Blueprint callback with its runtime arguments.

  ## Examples

      iex> Brando.Blueprint.Callback.call(fn value -> value * 2 end, [3])
      6

      iex> Brando.Blueprint.Callback.call({Map, :get, [:missing]}, [%{missing: 7}])
      7
  """
  @spec call(t(), [term()]) :: term()
  def call(callback, runtime_args) when is_function(callback) and is_list(runtime_args) do
    apply(callback, runtime_args)
  end

  def call({module, function, extra_args}, runtime_args)
      when is_atom(module) and is_atom(function) and is_list(extra_args) and is_list(runtime_args) do
    apply(module, function, runtime_args ++ extra_args)
  end
end
