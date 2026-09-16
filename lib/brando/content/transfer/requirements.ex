defmodule Brando.Content.Transfer.Requirements do
  use Gettext, backend: Brando.Gettext
  @moduledoc false

  # Definition defaults are reviewed separately. Only dependencies reachable
  # from the selected content belong to the atomic content operation.
  def content(bundle, mappings) do
    tokens = references([Enum.map(bundle["fields"], & &1["blocks"]), bundle["entries"] || []], bundle["dependencies"])

    tokens
    |> expand(bundle["dependencies"], mappings, MapSet.new())
    |> then(&Map.take(bundle["dependencies"], MapSet.to_list(&1)))
  end

  defp expand([], _, _, visited), do: visited

  defp expand([token | remaining], dependencies, mappings, visited) do
    if MapSet.member?(visited, token) do
      expand(remaining, dependencies, mappings, visited)
    else
      dependency =
        dependencies[token] ||
          Brando.Content.Transfer.Error.fail!(
            dgettext("content_transfer", "The dependency manifest has an undeclared relationship.")
          )

      nested =
        case dependency["kind"] do
          "module" -> Enum.reject([dependency["parent"], dependency["table_template"]], &is_nil/1)
          "gallery" -> references(dependency["objects"], dependencies)
          "video" -> if mappings[token] in [nil, "create"], do: references(dependency["data"], dependencies), else: []
          _ -> []
        end

      expand(nested ++ remaining, dependencies, mappings, MapSet.put(visited, token))
    end
  end

  def references(value, dependencies) when is_map(value),
    do: Enum.flat_map(value, fn {key, value} -> references(key, dependencies) ++ references(value, dependencies) end)

  def references(value, dependencies) when is_list(value), do: Enum.flat_map(value, &references(&1, dependencies))

  def references(value, dependencies) when is_binary(value) do
    if Map.has_key?(dependencies, value) do
      [value]
    else
      Regex.scan(~r/data-identifier-id\s*=\s*["']([^"']+)["']/i, value)
      |> Enum.map(&List.last/1)
      |> Enum.filter(&Map.has_key?(dependencies, &1))
    end
  end

  def references(_, _), do: []
end
