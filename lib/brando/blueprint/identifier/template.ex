defmodule Brando.Blueprint.Identifier.Template do
  @moduledoc """
  Backwards-compatible extraction of direct and one-level field references from
  Liquid identifier templates.

  Blueprint compilation uses its internal DSL verifier for preload extraction; that
  path supports arbitrary nesting and resolves only declared relations. This
  module retains the older public return shape without creating atoms or raising
  on unknown/deep paths.
  """

  @field_pattern ~r/\bentry((?:\.[a-zA-Z0-9_]+)+)/

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
    @field_pattern
    |> Regex.scan(template, capture: :all_but_first)
    |> Enum.flat_map(&extract_reference/1)
    |> Enum.uniq()
  end

  defp extract_reference([path]) do
    path
    |> String.trim_leading(".")
    |> String.split(".")
    |> existing_reference()
  end

  defp existing_reference([field]) do
    case existing_atom(field) do
      nil -> []
      field_atom -> [field_atom]
    end
  end

  defp existing_reference([relation, field]) do
    with relation_atom when not is_nil(relation_atom) <- existing_atom(relation),
         field_atom when not is_nil(field_atom) <- existing_atom(field) do
      [[{relation_atom, field_atom}]]
    else
      _ -> []
    end
  end

  defp existing_reference(_deep_path), do: []

  defp existing_atom(value) do
    String.to_existing_atom(value)
  rescue
    ArgumentError -> nil
  end
end
