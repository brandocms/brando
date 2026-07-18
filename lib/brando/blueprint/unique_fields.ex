defmodule Brando.Blueprint.UniqueFields do
  @moduledoc """
  Normalizes persisted fields for Blueprint unique constraints and indexes.

  Keeping this ordering in one dependency-light module ensures compile-time
  verification, runtime changesets, and migration snapshots interpret control
  values such as `prevent_collision: true` identically.
  """

  @doc """
  Returns the complete persisted field list for a unique declaration.
  """
  @spec fields(atom(), term()) :: [atom()]
  def fields(field, true), do: [field]

  def fields(field, unique_opts) when is_list(unique_opts) do
    collision_scope = Keyword.get(unique_opts, :prevent_collision)
    [field | scope(unique_opts, collision_scope)]
  end

  def fields(field, _unique), do: [field]

  @doc """
  Returns the persisted scope fields for a unique keyword declaration.

  An explicit `:with` scope takes precedence because it describes the database
  constraint for callback collision queries.
  """
  @spec scope(keyword(), term()) :: [atom()]
  def scope(unique_opts, collision_scope) do
    case Keyword.fetch(unique_opts, :with) do
      {:ok, fields} -> List.wrap(fields)
      :error -> collision_scope_fields(collision_scope)
    end
  end

  defp collision_scope_fields(field) when is_atom(field) and field not in [nil, false, true], do: [field]
  defp collision_scope_fields(fields) when is_list(fields), do: fields
  defp collision_scope_fields(_scope), do: []
end
