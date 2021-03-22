defmodule Brando.Blueprint.Relations do
  def build_relation(name, type, opts \\ []) do
    %{name: name, type: type, opts: Enum.into(opts, %{})}
  end

  defmacro relations(do: block) do
    relations(__CALLER__, block)
  end

  defp relations(_caller, block) do
    quote location: :keep do
      Module.register_attribute(__MODULE__, :relations, accumulate: true)
      unquote(block)
    end
  end

  defmacro relation(name, type, opts \\ []) do
    relation(__CALLER__, name, type, opts)
  end

  defp relation(_caller, name, type, opts) do
    quote location: :keep do
      rel =
        build_relation(
          unquote(name),
          unquote(type),
          unquote(opts)
        )

      Module.put_attribute(__MODULE__, :relations, rel)
    end
  end
end
