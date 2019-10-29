defmodule Brando.SoftDelete.Schema do
  @moduledoc """
  Macro for adding field to schema.
  """

  defmacro __using__(_) do
    quote do
      import unquote(__MODULE__)
      @before_compile unquote(__MODULE__)
    end
  end

  @doc false
  defmacro __before_compile__(_) do
    compile()
  end

  @doc false
  def compile do
    quote do
      def __soft_delete__ do
        true
      end
    end
  end

  @doc """
  Add soft delete field to schema
  """
  defmacro soft_delete do
    quote do
      field :deleted_at, :utc_datetime
    end
  end
end
