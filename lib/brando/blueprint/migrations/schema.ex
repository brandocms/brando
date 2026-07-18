defmodule Brando.Blueprint.Migrations.Schema do
  @moduledoc false

  alias Brando.Blueprint.Migrations.Types
  alias Brando.Exception.BlueprintError

  @format_version 2
  @column_opts [:default, :null, :precision, :scale]

  @type column :: %{
          required(:name) => atom(),
          required(:type) => atom() | tuple(),
          required(:opts) => map(),
          required(:reference) => map() | nil,
          optional(:rename_from) => atom()
        }

  @type index :: %{
          name: String.t(),
          table: String.t(),
          fields: [atom()],
          unique: boolean()
        }

  @type auxiliary_table :: %{
          name: String.t(),
          columns: [column()],
          indexes: [index()],
          timestamps: boolean()
        }

  @type t :: %{
          format_version: pos_integer(),
          table: String.t(),
          primary_key: :id | :uuid,
          columns: [column()],
          indexes: [index()],
          auxiliary_tables: [auxiliary_table()],
          timestamps: boolean()
        }

  @doc """
  Builds the storage-relevant schema for a Blueprint module.

  The returned map intentionally excludes form, listing, upload, and other
  runtime-only configuration so snapshots remain stable when those concerns
  change.
  """
  @spec build(module()) :: t()
  def build(module) do
    build_from(
      module,
      Brando.Blueprint.Attributes.__attributes__(module),
      Brando.Blueprint.Assets.__assets__(module),
      Brando.Blueprint.Relations.__relations__(module)
    )
  end

  @doc """
  Converts a legacy snapshot into the normalized storage schema.

  Legacy snapshots did not store the table or primary-key definition. Those
  values must therefore be recovered from the current module for the one-time
  format migration.
  """
  @spec from_legacy(module(), map()) :: t()
  def from_legacy(module, snapshot) do
    build_from(
      module,
      Map.get(snapshot, :attributes, []) || [],
      Map.get(snapshot, :assets, []) || [],
      Map.get(snapshot, :relations, []) || []
    )
  end

  @doc """
  Removes transient migration hints before a schema is persisted.
  """
  @spec persistable(t()) :: t()
  def persistable(schema) do
    update_in(schema.columns, &Enum.map(&1, fn column -> Map.delete(column, :rename_from) end))
  end

  @doc """
  Returns true when two columns have the same persisted storage definition.
  """
  @spec same_column?(column(), column()) :: boolean()
  def same_column?(left, right) do
    Map.delete(left, :rename_from) == Map.delete(right, :rename_from)
  end

  @doc """
  Validates a normalized storage schema loaded from a Blueprint snapshot.

  Validation is intentionally structural and fail-closed so malformed stored
  terms cannot be interpreted as column, index, or auxiliary-table removals.
  """
  @spec validate(term()) :: :ok | {:error, term()}
  def validate(schema) when is_map(schema) do
    with :ok <- validate_value(schema, :format_version, &(&1 == @format_version)),
         :ok <- validate_value(schema, :table, &non_empty_string?/1),
         :ok <- validate_value(schema, :primary_key, &(&1 in [:id, :uuid])),
         :ok <- validate_value(schema, :timestamps, &is_boolean/1),
         :ok <- validate_collection(schema, :columns, &validate_column/1),
         :ok <- validate_collection(schema, :indexes, &validate_index(&1, schema.table)),
         :ok <- validate_collection(schema, :auxiliary_tables, &validate_auxiliary_table/1),
         :ok <- validate_unique_names(schema.columns, :columns),
         :ok <- validate_unique_names(schema.indexes, :indexes) do
      validate_unique_names(schema.auxiliary_tables, :auxiliary_tables)
    end
  end

  def validate(schema), do: {:error, {:invalid_schema, schema}}

  defp validate_value(map, key, validator) do
    case Map.fetch(map, key) do
      {:ok, value} -> if validator.(value), do: :ok, else: {:error, {:invalid_field, key, value}}
      :error -> {:error, {:missing_field, key}}
    end
  end

  defp validate_collection(map, key, validator) do
    case Map.fetch(map, key) do
      {:ok, entries} when is_list(entries) -> validate_entries(entries, key, validator)
      {:ok, entries} -> {:error, {:invalid_field, key, entries}}
      :error -> {:error, {:missing_field, key}}
    end
  end

  defp validate_entries(entries, key, validator) do
    entries
    |> Enum.with_index()
    |> Enum.reduce_while(:ok, fn {entry, index}, :ok ->
      case validator.(entry) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {key, index, reason}}}
      end
    end)
  end

  defp validate_column(column) when is_map(column) do
    with :ok <- validate_value(column, :name, &valid_atom?/1),
         :ok <- validate_value(column, :type, &valid_migration_type?/1),
         :ok <- validate_value(column, :opts, &valid_column_opts?/1),
         :ok <- validate_reference(Map.get(column, :reference)) do
      validate_optional_atom(column, :rename_from)
    end
  end

  defp validate_column(column), do: {:error, {:invalid_column, column}}

  defp validate_reference(nil), do: :ok

  defp validate_reference(reference) when is_map(reference) do
    with :ok <- validate_value(reference, :table, &non_empty_string?/1),
         :ok <- validate_value(reference, :type, &valid_migration_type?/1),
         :ok <- validate_value(reference, :column, &valid_atom?/1),
         :ok <- validate_value(reference, :on_delete, &valid_atom?/1) do
      validate_value(reference, :name, &non_empty_string?/1)
    end
  end

  defp validate_reference(reference), do: {:error, {:invalid_reference, reference}}

  defp validate_index(index, expected_table) when is_map(index) do
    with :ok <- validate_value(index, :name, &non_empty_string?/1),
         :ok <- validate_value(index, :table, &(&1 == expected_table)),
         :ok <- validate_value(index, :unique, &is_boolean/1) do
      validate_value(index, :fields, &valid_fields?/1)
    end
  end

  defp validate_index(index, _expected_table), do: {:error, {:invalid_index, index}}

  defp validate_auxiliary_table(table) when is_map(table) do
    with :ok <- validate_value(table, :name, &non_empty_string?/1),
         :ok <- validate_value(table, :timestamps, &is_boolean/1),
         :ok <- validate_collection(table, :columns, &validate_column/1),
         :ok <- validate_collection(table, :indexes, &validate_index(&1, table.name)),
         :ok <- validate_unique_names(table.columns, :columns) do
      validate_unique_names(table.indexes, :indexes)
    end
  end

  defp validate_auxiliary_table(table), do: {:error, {:invalid_auxiliary_table, table}}

  defp validate_unique_names(entries, key) do
    names = Enum.map(entries, &Map.get(&1, :name))
    if length(names) == MapSet.size(MapSet.new(names)), do: :ok, else: {:error, {:duplicate_names, key}}
  end

  defp validate_optional_atom(map, key) do
    case Map.fetch(map, key) do
      :error -> :ok
      {:ok, nil} -> :ok
      {:ok, value} -> if valid_atom?(value), do: :ok, else: {:error, {:invalid_field, key, value}}
    end
  end

  defp non_empty_string?(value), do: is_binary(value) and value != ""
  defp valid_atom?(value), do: is_atom(value) and not is_nil(value)
  defp valid_fields?(fields), do: is_list(fields) and fields != [] and Enum.all?(fields, &valid_atom?/1)

  defp valid_migration_type?(type) do
    (is_atom(type) or is_tuple(type)) and valid_storage_term?(type)
  end

  defp valid_column_opts?(opts) when is_map(opts) do
    Enum.all?(Map.keys(opts), &(&1 in @column_opts)) and valid_storage_term?(opts)
  end

  defp valid_column_opts?(_opts), do: false

  defp valid_storage_term?(term)
       when is_atom(term) or is_number(term) or is_bitstring(term),
       do: true

  defp valid_storage_term?(term) when is_list(term), do: Enum.all?(term, &valid_storage_term?/1)

  defp valid_storage_term?(term) when is_tuple(term) do
    term |> Tuple.to_list() |> Enum.all?(&valid_storage_term?/1)
  end

  defp valid_storage_term?(term) when is_map(term) do
    term
    |> Map.to_list()
    |> Enum.all?(fn {key, value} -> valid_storage_term?(key) and valid_storage_term?(value) end)
  end

  defp valid_storage_term?(_term), do: false

  defp build_from(module, attributes, assets, relations) do
    table = module.__naming__().table_name
    primary_key = primary_key_type(module)
    timestamps? = timestamped?(attributes)

    attribute_columns =
      attributes
      |> Enum.reject(&(timestamp_attribute?(&1) or Map.get(&1.opts, :virtual, false) == true))
      |> Enum.map(&attribute_column/1)

    asset_columns = Enum.map(assets, &asset_column(&1, table))
    relation_columns = Enum.flat_map(relations, &relation_columns(&1, module, table))

    columns =
      (attribute_columns ++ asset_columns ++ relation_columns)
      |> Enum.uniq_by(& &1.name)
      |> Enum.sort_by(& &1.name)

    indexes =
      (attribute_indexes(attributes, table) ++ relation_indexes(relations, table))
      |> Enum.uniq_by(& &1.name)
      |> Enum.sort_by(& &1.name)

    auxiliary_tables =
      relations
      |> Enum.flat_map(&auxiliary_tables(&1, table, primary_key))
      |> Enum.uniq_by(& &1.name)
      |> Enum.sort_by(& &1.name)

    %{
      format_version: @format_version,
      table: table,
      primary_key: primary_key,
      columns: columns,
      indexes: indexes,
      auxiliary_tables: auxiliary_tables,
      timestamps: timestamps?
    }
  end

  defp attribute_column(attribute) do
    opts = Map.take(attribute.opts, @column_opts)

    column = %{
      name: attribute.name,
      type: Types.migration_type(attribute.type),
      opts: opts,
      reference: nil
    }

    case Map.get(attribute.opts, :rename_from) do
      rename_from when is_atom(rename_from) -> Map.put(column, :rename_from, rename_from)
      _ -> column
    end
  end

  defp asset_column(asset, owner_table) do
    referenced_table =
      case asset.type do
        :image -> "images"
        :video -> "videos"
        :file -> "files"
        :gallery -> "galleries"
      end

    column_name = :"#{asset.name}_id"

    %{
      name: column_name,
      type: :id,
      opts: %{},
      reference: reference(owner_table, column_name, referenced_table, :id, :nilify_all)
    }
  end

  defp relation_columns(%{type: :belongs_to, name: name, opts: opts}, owner_module, owner_table) do
    referenced_module = Map.fetch!(opts, :module)
    referenced_table = referenced_table!(referenced_module)
    column_name = Map.get(opts, :foreign_key, :"#{name}_id")
    reference_type = referenced_primary_key_type(referenced_module, opts)
    on_delete = on_delete_strategy(opts, name, owner_module)

    [
      %{
        name: column_name,
        type: reference_type,
        opts: Map.take(opts, @column_opts),
        reference:
          reference(
            owner_table,
            column_name,
            referenced_table,
            reference_type,
            on_delete,
            Map.get(opts, :references, :id),
            Map.get(opts, :constraint_name)
          )
      }
    ]
  end

  defp relation_columns(%{type: type, name: name}, _owner_module, _owner_table)
       when type in [:embeds_one, :embeds_many, :image] do
    [%{name: name, type: :jsonb, opts: %{}, reference: nil}]
  end

  defp relation_columns(%{type: :has_many, name: name, opts: %{module: :blocks}}, _owner_module, _owner_table) do
    [
      %{name: :"rendered_#{name}", type: :text, opts: %{}, reference: nil},
      %{name: :"rendered_#{name}_at", type: :utc_datetime, opts: %{}, reference: nil}
    ]
  end

  defp relation_columns(_relation, _owner_module, _owner_table), do: []

  defp attribute_indexes(attributes, table) do
    Enum.flat_map(attributes, fn attribute ->
      language_index =
        if attribute.type == :language and !Map.get(attribute.opts, :virtual, false) do
          [index(table, [attribute.name], false)]
        else
          []
        end

      language_index ++ unique_attribute_index(attribute, table)
    end)
  end

  defp unique_attribute_index(%{opts: %{virtual: true}}, _table), do: []

  defp unique_attribute_index(attribute, table) do
    case Map.get(attribute.opts, :unique, false) do
      false -> []
      nil -> []
      unique -> [index(table, unique_fields(attribute.name, unique), true)]
    end
  end

  defp relation_indexes(relations, table) do
    Enum.flat_map(relations, fn
      %{type: :belongs_to, name: name, opts: opts} ->
        case Map.get(opts, :unique, false) do
          false ->
            []

          nil ->
            []

          unique ->
            foreign_key = Map.get(opts, :foreign_key, :"#{name}_id")
            [index(table, unique_fields(foreign_key, unique), true)]
        end

      _ ->
        []
    end)
  end

  defp unique_fields(field, true), do: [field]

  defp unique_fields(field, opts) when is_list(opts) do
    additional_fields =
      cond do
        Keyword.has_key?(opts, :with) -> List.wrap(Keyword.fetch!(opts, :with))
        is_atom(Keyword.get(opts, :prevent_collision)) -> [Keyword.fetch!(opts, :prevent_collision)]
        is_list(Keyword.get(opts, :prevent_collision)) -> Keyword.fetch!(opts, :prevent_collision)
        true -> []
      end

    [field | additional_fields]
  end

  defp unique_fields(field, _), do: [field]

  defp auxiliary_tables(%{type: :has_many, name: name, opts: %{module: :blocks}}, owner_table, owner_key_type) do
    table = "#{owner_table}_#{name}"

    [
      %{
        name: table,
        columns: [
          reference_column(table, :entry_id, owner_table, owner_key_type, :delete_all),
          reference_column(table, :block_id, "content_blocks", :id, :delete_all),
          %{name: :sequence, type: :integer, opts: %{}, reference: nil}
        ],
        indexes: [index(table, [:entry_id, :block_id], true)],
        timestamps: false
      }
    ]
  end

  defp auxiliary_tables(%{type: :entries, name: name}, owner_table, owner_key_type) do
    table = "#{owner_table}_#{name}_identifiers"

    [
      %{
        name: table,
        columns: [
          reference_column(table, :parent_id, owner_table, owner_key_type, :delete_all),
          reference_column(table, :identifier_id, "content_identifiers", :id, :delete_all),
          %{name: :sequence, type: :integer, opts: %{}, reference: nil}
        ],
        indexes: [index(table, [:parent_id, :identifier_id], true)],
        timestamps: true
      }
    ]
  end

  defp auxiliary_tables(
         %{type: :has_many, name: :alternates, opts: %{module: :alternates}},
         owner_table,
         owner_key_type
       ) do
    table = "#{owner_table}_alternates"

    [
      %{
        name: table,
        columns: [
          reference_column(table, :entry_id, owner_table, owner_key_type, :delete_all),
          reference_column(table, :linked_entry_id, owner_table, owner_key_type, :delete_all)
        ],
        indexes: [index(table, [:entry_id, :linked_entry_id], true)],
        timestamps: true
      }
    ]
  end

  defp auxiliary_tables(_relation, _owner_table, _owner_key_type), do: []

  defp reference_column(owner_table, name, referenced_table, type, on_delete) do
    %{
      name: name,
      type: type,
      opts: %{},
      reference: reference(owner_table, name, referenced_table, type, on_delete)
    }
  end

  defp reference(owner_table, column, table, type, on_delete, referenced_column \\ :id, constraint_name \\ nil) do
    %{
      table: table,
      type: type,
      column: referenced_column,
      on_delete: on_delete,
      name: constraint_name || "#{owner_table}_#{column}_fkey"
    }
  end

  defp index(table, fields, unique) do
    %{
      name: "#{table}_#{Enum.join(fields, "_")}_index",
      table: table,
      fields: fields,
      unique: unique
    }
  end

  defp primary_key_type(module) do
    case module.__primary_key__() do
      {:id, :binary_id, _opts} -> :uuid
      _ -> :id
    end
  end

  defp referenced_primary_key_type(module, opts) do
    case Map.get(opts, :type) do
      type when type in [:binary_id, :uuid] -> :uuid
      nil -> module_primary_key_type(module)
      type -> type
    end
  end

  defp module_primary_key_type(module) do
    if Code.ensure_loaded?(module) do
      cond do
        function_exported?(module, :__primary_key__, 0) and
            match?({:id, :binary_id, _}, module.__primary_key__()) ->
          :uuid

        function_exported?(module, :__schema__, 2) and module.__schema__(:type, :id) == :binary_id ->
          :uuid

        true ->
          :id
      end
    else
      :id
    end
  end

  defp referenced_table!(module) do
    if Code.ensure_loaded?(module) and function_exported?(module, :__schema__, 1) do
      module.__schema__(:source)
    else
      raise BlueprintError,
        message: "Cannot generate migration reference for #{inspect(module)}: module is not an Ecto schema"
    end
  end

  defp timestamped?(attributes) do
    names = MapSet.new(attributes, & &1.name)
    MapSet.member?(names, :inserted_at) and MapSet.member?(names, :updated_at)
  end

  defp timestamp_attribute?(%{name: name}), do: name in [:inserted_at, :updated_at]

  defp on_delete_strategy(opts, name, owner_module) do
    cond do
      Map.has_key?(opts, :on_delete) -> Map.fetch!(opts, :on_delete)
      name in [:cover, :image, :avatar, :meta_image, :file] -> :nilify_all
      join_table?(owner_module) -> :delete_all
      true -> :nothing
    end
  end

  defp join_table?(module) do
    relations = Brando.Blueprint.Relations.__relations__(module)
    belongs_to_count = Enum.count(relations, &(&1.type == :belongs_to))
    ignorable_attrs = [:sequence, :inserted_at, :updated_at, :marked_as_deleted, :deleted_at]

    significant_attrs =
      module
      |> Brando.Blueprint.Attributes.__attributes__()
      |> Enum.reject(&(&1.name in ignorable_attrs))

    belongs_to_count == 2 and significant_attrs == []
  rescue
    _ -> false
  end
end
