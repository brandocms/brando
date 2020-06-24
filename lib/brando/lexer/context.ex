defmodule Brando.Lexer.Context do
  @moduledoc """
  Stores contextual information for the parser
  """

  alias Brando.Utils

  defstruct variables: %{},
            cycles: %{},
            private: %{},
            filter_module: Brando.Lexer.Filter,
            render_module: nil

  @type t :: %__MODULE__{
          variables: map(),
          cycles: map(),
          private: map(),
          filter_module: module,
          render_module: module | nil
        }

  @spec new(map()) :: t()
  @doc """
  Create a new `Context.t` using predefined `variables` map
  Returns a new, initialized context object
  """
  def new(variables), do: %__MODULE__{variables: stringify_if_map(variables)}

  @spec assign(t(), String.t(), any) :: t()
  @doc """
  Assign a new variable to the `context`
  Set a variable named `key` with the given `value` in the current context
  """
  def assign(%__MODULE__{variables: variables} = context, key, value) do
    updated_variables = Map.put(variables, to_string(key), stringify_if_map(value))
    %{context | variables: updated_variables}
  end

  defp stringify_if_map(value) when is_map(value), do: Utils.stringify_keys(value)
  defp stringify_if_map(value), do: value
end
