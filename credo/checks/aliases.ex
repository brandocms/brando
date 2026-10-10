defmodule Brando.Credo.Aliases do
  @moduledoc false
  # The `alias` declarations of a source file, for Brando's own Credo checks:
  # `collect/1` maps each short name to its full module parts, `expand/2`
  # resolves a module reference through that map. An alias built on an
  # earlier one (`alias Ecto.Adapters.SQL` then `alias SQL.Sandbox`) resolves
  # through it, in declaration order. Scope is file-wide.

  def collect(ast) do
    {_ast, aliases} = Macro.prewalk(ast, %{}, fn node, acc -> {node, add_alias(node, acc)} end)
    aliases
  end

  def expand([head | rest], aliases) do
    case Map.fetch(aliases, head) do
      {:ok, full} -> full ++ rest
      :error -> [head | rest]
    end
  end

  def expand(parts, _aliases), do: parts

  defp add_alias({:alias, _, [{:__aliases__, _, parts}]}, acc) when is_list(parts) do
    Map.put(acc, Enum.at(parts, -1), expand(parts, acc))
  end

  defp add_alias({:alias, _, [{:__aliases__, _, parts}, [as: {:__aliases__, _, [name]}]]}, acc) do
    Map.put(acc, name, expand(parts, acc))
  end

  defp add_alias({:alias, _, [{{:., _, [{:__aliases__, _, base}, :{}]}, _, children}]}, acc) do
    base = expand(base, acc)

    Enum.reduce(children, acc, fn
      {:__aliases__, _, parts}, acc -> Map.put(acc, Enum.at(parts, -1), base ++ parts)
      _child, acc -> acc
    end)
  end

  defp add_alias(_node, acc), do: acc
end
