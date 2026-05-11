defmodule Brando.Blueprint.Migrations.Operations.Relation.Add do
  # import Brando.Blueprint.Migrations.Types
  @moduledoc false
  defstruct relation: nil,
            module: nil,
            opts: nil

  def up(%{relation: %{type: :has_many, name: name, opts: %{module: :blocks}}}) do
    """
    add :rendered_#{name}, :text
    add :rendered_#{name}_at, :utc_datetime
    """
  end

  def up(%{relation: %{type: :belongs_to, name: name, opts: %{module: referenced_module} = opts}, module: owner_module}) do
    referenced_table = referenced_module.__schema__(:source)
    uuid? = referenced_module.__primary_key__() == {:id, :binary_id, autogenerate: true}
    on_delete = get_on_delete_strategy(opts, name, owner_module)

    if uuid? do
      """
      add #{inspect(name)}_id, references(:#{referenced_table}, on_delete: #{inspect(on_delete)}, type: :uuid)
      """
    else
      """
      add #{inspect(name)}_id, references(:#{referenced_table}, on_delete: #{inspect(on_delete)})
      """
    end
  end

  def up(%{relation: %{type: :image, name: name}}) do
    """
    add #{inspect(name)}, :jsonb
    """
  end

  # entries are handled as a m2m now
  def up(%{relation: %{type: :entries, name: _name}}) do
    """
    """
  end

  def up(%{relation: %{type: :embeds_many, name: name, opts: %{module: _}}}) do
    """
    add #{inspect(name)}, :jsonb
    """
  end

  def up(%{relation: %{type: :embeds_one, name: name, opts: %{module: _}}}) do
    """
    add #{inspect(name)}, :jsonb
    """
  end

  def up(%{relation: _}) do
    ""
  end

  def down(%{relation: %{type: :has_many, name: name, opts: %{module: :blocks}}}) do
    """
    remove :rendered_#{name}
    remove :rendered_#{name}_at
    """
  end

  def down(%{relation: %{type: :belongs_to, name: name}}) do
    """
    remove #{inspect(name)}_id
    """
  end

  def down(%{relation: %{type: :image, name: name}}) do
    """
    remove #{inspect(name)}
    """
  end

  # entries are handled as an m2m now
  def down(%{relation: %{type: :entries, name: _}}) do
    """
    """
  end

  def down(%{relation: %{type: :embeds_many, name: name, opts: %{module: _}}}) do
    """
    remove #{inspect(name)}
    """
  end

  def down(%{relation: %{type: :embeds_one, name: name, opts: %{module: _}}}) do
    """
    remove #{inspect(name)}
    """
  end

  def down(%{relation: _}) do
    ""
  end

  def up_indexes(%{relation: %{type: :belongs_to, name: name, opts: %{unique: [with: other_fields]}}, module: module})
      when is_list(other_fields) do
    table_name = module.__naming__().table_name

    name_id = String.to_existing_atom("#{name}_id")

    """
    create unique_index(:#{table_name}, #{inspect([name_id] ++ other_fields)})
    """
  end

  def up_indexes(%{relation: %{type: :belongs_to, name: name, opts: %{unique: [with: other_field]}}, module: module})
      when is_atom(other_field) do
    table_name = module.__naming__().table_name

    """
    create unique_index(:#{table_name}, [:#{name}_id, :#{other_field}])
    """
  end

  def up_indexes(_) do
    ""
  end

  def down_indexes(_) do
    ""
  end

  # Private helpers

  # Determines the appropriate on_delete strategy for a belongs_to relation.
  #
  # Strategy:
  # 1. If explicitly set in opts, use that
  # 2. If relation is for images/files, use :nilify_all
  # 3. If owner module is a join table, use :delete_all
  # 4. Otherwise default to :nothing (safe default)
  defp get_on_delete_strategy(opts, name, owner_module) do
    cond do
      # Explicitly configured - respect user's choice
      Map.has_key?(opts, :on_delete) ->
        Map.get(opts, :on_delete)

      # Image/file references should nilify
      name in [:cover, :image, :avatar, :meta_image, :file] ->
        :nilify_all

      # Join tables should cascade delete
      join_table?(owner_module) ->
        :delete_all

      # Safe default
      true ->
        :nothing
    end
  end

  # Detects if a module is a join table based on its structure.
  #
  # A join table is characterized by:
  # - Exactly 2 belongs_to relations
  # - Minimal other attributes (only sequence, timestamps, etc.)
  # - Often has @allow_mark_as_deleted = true
  defp join_table?(module) do
    alias Brando.Blueprint.{Attributes, Relations}

    # Get all relations using the Blueprint API
    relations = Relations.__relations__(module)
    belongs_to_relations = Enum.filter(relations, &(&1.type == :belongs_to))
    belongs_to_count = length(belongs_to_relations)

    # Get attributes (excluding timestamps which are always there)
    attrs = Attributes.__attributes__(module)

    # Common join table attributes to ignore in the count
    ignorable_attrs = [:sequence, :inserted_at, :updated_at, :marked_as_deleted, :deleted_at]
    significant_attrs = Enum.reject(attrs, fn attr -> attr.name in ignorable_attrs end)
    significant_attrs_count = length(significant_attrs)

    # Join table: exactly 2 belongs_to relations and no/minimal other attributes
    belongs_to_count == 2 && significant_attrs_count == 0
  rescue
    # If anything fails, default to false (safe)
    _ -> false
  end
end
