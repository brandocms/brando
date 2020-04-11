defmodule Brando.Generators.Migration do
  def before_copy(binding) do
    binding
    |> add_migration_fields
    |> add_migration_indexes
    |> add_migration_assocs
  end

  def after_copy(binding) do
    binding
  end

  defp add_migration_fields(binding) do
    attrs = Keyword.get(binding, :attrs)
    migration_types = Keyword.get(binding, :migration_types)
    defaults = Keyword.get(binding, :defaults)

    migration_fields =
      Enum.map(attrs, fn {k, v} ->
        case v do
          :villain -> (k == :data && "villain()") || "villain #{inspect(k)}"
          :gallery -> (k == :image_series && "gallery()") || "gallery #{inspect(k)}"
          _ -> "add #{inspect(k)}, #{inspect(migration_types[k])}#{defaults[k]}"
        end
      end)

    Keyword.put(binding, :migration_fields, migration_fields)
  end

  defp add_migration_indexes(binding) do
    assocs = Keyword.get(binding, :assocs)
    snake_domain = Keyword.get(binding, :snake_domain)
    plural = Keyword.get(binding, :plural)

    indexes =
      Enum.reduce(assocs, [], fn {key, _}, acc ->
        ["create index(:#{snake_domain}_#{plural}, [:#{key}_id])" | acc]
      end)

    Keyword.put(binding, :indexes, indexes)
  end

  defp add_migration_assocs(binding) do
    assocs = Keyword.get(binding, :assocs)

    migration_assocs =
      Enum.reduce(assocs, [], fn
        {key, {:references, target}}, acc ->
          [{key, :"#{key}_id", target, :nothing} | acc]
      end)

    Keyword.put(binding, :migration_assocs, migration_assocs)
  end
end
