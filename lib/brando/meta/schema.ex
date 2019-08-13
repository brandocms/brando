defmodule Brando.Meta.Schema do
  @moduledoc """
  Macro for mapping META fields to schema
  """

  @doc false
  defmacro __using__(_) do
    import Brando.Meta.Schema
  end
  
  defmacro meta_schema([do: block]) do
    quote do
      Module.register_attribute(:meta_fields, accumulate: true)
    end
  end
  
  defmacro field(name, path, mutator_function) do
    Module.put_attribute(:meta_fields, name)
    
    quote do
      def __meta_field__(name, data) do
        value = get_in(data, Enum.map(unquote(path), &Access.get/1))
        unquote(mutator_function).(value)
      end
    end
  end
end
