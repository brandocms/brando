defmodule Brando.Blueprint.Identifier.Template do
  @moduledoc """
  Parses identifier template strings to extract referenced fields.

  Used at compile time to determine which fields need to be preloaded
  when generating identifiers for entries.
  """

  @doc """
  Extracts field references from a Liquex template string.

  Parses templates like `"{{ entry.title }} [{{ entry.creator.name }}]"`
  and extracts the referenced fields for preloading.

  ## Examples

      iex> extract_fields("{{ entry.title }}")
      [:title]

      iex> extract_fields("{{ entry.title }} [{{ entry.creator.name }}]")
      [:title, [{:creator, :name}]]

      iex> extract_fields("{{ entry.name }} - {{ entry.category.title }}")
      [:name, [{:category, :title}]]

  """
  @spec extract_fields(String.t()) :: [atom() | [{atom(), atom()}]]
  def extract_fields(template) do
    regex = ~r/.*?(entry[.a-zA-Z0-9_]+).*?/

    matches =
      regex
      |> Regex.scan(template, capture: :all_but_first)
      |> Enum.map(&String.split(List.first(&1), "."))
      |> Enum.filter(&(Enum.count(&1) > 1))

    matches
    |> Enum.map(fn
      [_, rel, f] -> [{String.to_existing_atom(rel), String.to_existing_atom(f)}]
      [_, f] -> String.to_existing_atom(f)
    end)
    |> Enum.reject(&is_nil(&1))
    |> Enum.uniq()
  end
end
