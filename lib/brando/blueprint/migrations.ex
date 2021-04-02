defmodule Brando.Blueprint.Migrations do
  alias Brando.Blueprint.Snapshot

  alias Brando.Blueprint.Migrations.Operations
  alias Brando.Blueprint.Attribute
  alias Brando.Blueprint.Relation

  @default_opts [
    migration_path: "priv/repo/migration",
    snapshot_path: "priv/blueprints/snapshots"
  ]

  def create_migration(module, opts \\ @default_opts) do
    current_snapshot = Snapshot.build_snapshot(module)
    previous_snapshot = Snapshot.get_latest_snapshot(module, opts)

    current_snapshot
    |> diff_against(previous_snapshot)
    |> do_create_migration(module, opts)
  end

  def do_create_migration(
        {
          [],
          [],
          [],
          []
        },
        _module,
        _opts
      ) do
    nil
  end

  def do_create_migration(
        {
          attributes_to_add,
          attributes_to_remove,
          relations_to_add,
          relations_to_remove
        },
        module,
        opts
      ) do
    {operation_type, operations} =
      build_operations(
        attributes_to_add,
        attributes_to_remove,
        relations_to_add,
        relations_to_remove,
        module,
        opts
      )

    up = perform_operations(:up, operations)
    down = perform_operations(:down, operations)

    up_indexes = perform_operations(:up_indexes, operations)
    down_indexes = perform_operations(:down_indexes, operations)

    sequence = get_sequence(module, opts)

    wrap_in_operation_type(
      {up, down},
      {up_indexes, down_indexes},
      operation_type,
      module,
      sequence
    )
    |> format_code()
    |> write_migration(module, sequence, opts)
    |> Snapshot.store_snapshot(opts)
  end

  defp write_migration(contents, module, sequence, opts) do
    module
    |> build_migration_filename(sequence, opts)
    |> File.write!(contents)

    module
  end

  defp format_code(content) do
    Code.format_string!(content, locals_without_parens: locals_without_parens())
  end

  defp wrap_in_operation_type({up, _}, {up_indexes, down_indexes}, :create, module, sequence) do
    application = module.__naming__().application
    domain = module.__naming__().domain
    schema = module.__naming__().schema
    table_name = module.__naming__().table_name
    migration_module = "#{application}.Migrations.#{domain}.#{schema}.Blueprint#{sequence}"

    """
    defmodule #{migration_module} do
      use Ecto.Migration

      def up do
        create table(:#{table_name}) do
          #{up}
        end

        #{up_indexes}
      end

      def down do
        drop table(:#{table_name})

        #{down_indexes}
      end
    end
    """
  end

  defp wrap_in_operation_type({up, down}, {up_indexes, down_indexes}, :alter, module, sequence) do
    application = module.__naming__().application
    domain = module.__naming__().domain
    schema = module.__naming__().schema
    table_name = module.__naming__().table_name
    migration_module = "#{application}.Migrations.#{domain}.#{schema}.Blueprint#{sequence}"

    """
    defmodule #{migration_module} do
      use Ecto.Migration

      def up do
        alter table(:#{table_name}) do
          #{up}
        end

        #{up_indexes}
      end

      def down do
        alter table(:#{table_name}) do
          #{down}
        end

        #{down_indexes}
      end
    end
    """
  end

  def diff_against(current_snapshot, nil) do
    attributes_to_add = current_snapshot.attributes
    relations_to_add = current_snapshot.relations
    {attributes_to_add, [], relations_to_add, []}
  end

  def diff_against(current_snapshot, previous_snapshot) do
    attributes_to_add =
      Enum.reject(current_snapshot.attributes, fn attribute ->
        Enum.find(previous_snapshot.attributes, &(&1.name == attribute.name))
      end)

    attributes_to_remove =
      Enum.reject(previous_snapshot.attributes, fn attribute ->
        Enum.find(current_snapshot.attributes, &(&1.name == attribute.name))
      end)

    relations_to_add =
      Enum.reject(current_snapshot.relations, fn relation ->
        Enum.find(previous_snapshot.relations, &(&1.name == relation.name))
      end)

    relations_to_remove =
      Enum.reject(previous_snapshot.relations, fn relation ->
        Enum.find(current_snapshot.relations, &(&1.name == relation.name))
      end)

    {attributes_to_add, attributes_to_remove, relations_to_add, relations_to_remove}
  end

  def build_operations(
        attributes_to_add,
        attributes_to_remove,
        relations_to_add,
        relations_to_remove,
        module,
        opts
      ) do
    # are we creating a table or altering?
    operation_type = operation_type(module, opts)
    additive_actions = attributes_to_add ++ relations_to_add
    additive_operations = Enum.map(additive_actions, &build_operation(:add, &1, module))

    reductive_actions = attributes_to_remove ++ relations_to_remove
    reductive_operations = Enum.map(reductive_actions, &build_operation(:remove, &1, module))

    operations = additive_operations ++ reductive_operations

    {operation_type, operations}
  end

  defp operation_type(module, opts) do
    # do we have any existing migrations for this?
    case get_latest_migration(module, opts) do
      nil -> :create
      _ -> :alter
    end
  end

  defp get_sequence(module, opts) do
    case get_latest_migration(module, opts) do
      nil ->
        pad_sequence(1)

      last_migration ->
        last_migration
        |> Path.basename(".exs")
        |> String.split("_")
        |> List.last()
        |> String.to_integer()
        |> Kernel.+(1)
        |> pad_sequence()
    end
  end

  defp build_migration_filename(module, sequence, opts) do
    filename_core = build_filename_core(module)
    build_migration_path("#{timestamp()}_#{filename_core}_#{sequence}.exs", opts)
  end

  defp pad_sequence(number) do
    String.pad_leading(to_string(number), 3, "0")
  end

  defp timestamp do
    {{y, m, d}, {hh, mm, ss}} = :calendar.universal_time()
    "#{y}#{pad(m)}#{pad(d)}#{pad(hh)}#{pad(mm)}#{pad(ss)}"
  end

  defp pad(i) when i < 10, do: <<?0, ?0 + i>>
  defp pad(i), do: to_string(i)

  defp build_filename_core(module) do
    application = module.__naming__().application
    domain = module.__naming__().domain
    schema = module.__naming__().schema
    String.downcase("blueprint_#{application}_#{domain}_#{schema}")
  end

  defp build_migration_path(file, opts) do
    migration_path = Keyword.get(opts, :migration_path, "priv/repo/migrations")
    File.mkdir_p!(migration_path)

    Path.join([
      migration_path,
      file
    ])
  end

  defp get_latest_migration(module, opts) do
    filename_core = build_filename_core(module)
    filename_glob = String.downcase("*_#{filename_core}_*.exs")
    migration_path = build_migration_path(filename_glob, opts)

    case Path.wildcard(migration_path) do
      [] ->
        nil

      migrations ->
        List.last(migrations)
    end
  end

  defp build_operation(:add, %Attribute{} = attr, module) do
    %Operations.Attribute.Add{
      attribute: attr,
      module: module
    }
  end

  defp build_operation(:add, %Relation{} = rel, module) do
    ecto_data = Map.get(module.__changeset__, rel.name)

    %Operations.Relation.Add{
      relation: rel,
      module: module,
      opts: ecto_data
    }
  end

  defp build_operation(:remove, %Attribute{} = attr, module) do
    %Operations.Attribute.Remove{
      attribute: attr,
      module: module
    }
  end

  defp build_operation(:remove, %Relation{} = rel, module) do
    ecto_data = Map.get(module.__changeset__, rel.name)

    %Operations.Relation.Remove{
      relation: rel,
      module: module,
      opts: ecto_data
    }
  end

  def perform_operations(operation, operations) do
    Enum.map(operations, &apply(&1.__struct__(), operation, [&1]))
  end

  defp locals_without_parens do
    path = Path.join(File.cwd!(), "deps/ecto_sql/.formatter.exs")

    if File.exists?(path) do
      {formatter_opts, _} = Code.eval_file(path)
      Keyword.get(formatter_opts, :locals_without_parens, [])
    else
      []
    end
  end
end
