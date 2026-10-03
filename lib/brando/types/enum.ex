defmodule Brando.Type.Enum do
  defmacro __using__(attrs) do
    quote do
      Module.put_attribute(__MODULE__, :enum, unquote(attrs))

      use Ecto.Type
      import unquote(__MODULE__)
      @impl true
      def type, do: :integer
      @before_compile unquote(__MODULE__)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    attrs = Module.get_attribute(env.module, :enum)
    compile(attrs)
  end

  defp compile(attrs) do
    attrs_cast = for {val, idx} <- Enum.with_index(attrs), do: defenumcast(val, idx)
    attrs_load = for {val, idx} <- Enum.with_index(attrs), do: defenumload(val, idx)
    attrs_dump = for {val, idx} <- Enum.with_index(attrs), do: defenumdump(val, idx)

    quote do
      unquote(attrs_cast)
      unquote(attrs_load)
      unquote(attrs_dump)
    end
  end

  defp defenumcast(val, idx) do
    str = Atom.to_string(val)

    quote do
      @impl true
      def cast(unquote(idx)), do: {:ok, unquote(val)}
      def cast(unquote(val)), do: {:ok, unquote(val)}
      def cast(unquote(str)), do: {:ok, unquote(val)}
    end
  end

  defp defenumload(val, idx) do
    quote do
      @impl true
      def load(unquote(idx)), do: {:ok, unquote(val)}
    end
  end

  defp defenumdump(val, idx) do
    quote do
      @impl true
      def dump(unquote(val)), do: {:ok, unquote(idx)}
    end
  end
end
