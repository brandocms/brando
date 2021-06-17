defmodule Brando.Blueprint.Migrations.Operations.Attribute.Remove do
  import Brando.Blueprint.Migrations.Types

  defstruct attribute: nil,
            module: nil

  def down(%{attribute: %{name: :inserted_at}}) do
    """
    timestamps()
    """
  end

  def down(%{attribute: %{name: :updated_at}}), do: ""

  def down(%{attribute: attr}) do
    """
    add #{inspect(attr.name)}, #{inspect(migration_type(attr.type))}
    """
  end

  def up(%{attribute: %{name: :inserted_at}}) do
    """
    remove :inserted_at
    """
  end

  def up(%{attribute: %{name: :updated_at}}) do
    """
    remove :updated_at
    """
  end

  def up(%{attribute: attr}) do
    """
    remove #{inspect(attr.name)}
    """
  end

  def down_indexes(%{attribute: %{name: name, type: :language, opts: _opts}, module: module}) do
    table_name = module.__naming__().table_name

    """
    create index(:#{table_name}, [:#{name}])
    """
  end

  def down_indexes(%{
        attribute: %{name: name, opts: %{unique: [prevent_collision: true]}},
        module: module
      }) do
    table_name = module.__naming__().table_name

    """
    create unique_index(:#{table_name}, [:#{name}])
    """
  end

  def down_indexes(%{
        attribute: %{name: name, opts: %{unique: true}},
        module: module
      }) do
    table_name = module.__naming__().table_name

    """
    create unique_index(:#{table_name}, [:#{name}])
    """
  end

  def down_indexes(%{
        attribute: %{name: name, opts: %{unique: [with: other_fields]}},
        module: module
      })
      when is_list(other_fields) do
    table_name = module.__naming__().table_name

    """
    create unique_index(:#{table_name}, #{inspect([name] ++ other_fields)})
    """
  end

  def down_indexes(%{
        attribute: %{name: name, opts: %{unique: [with: other_field]}},
        module: module
      })
      when is_atom(other_field) do
    table_name = module.__naming__().table_name

    """
    create unique_index(:#{table_name}, [:#{name}, :#{other_field}])
    """
  end

  def down_indexes(%{
        attribute: %{name: name, opts: %{unique: [prevent_collision: coll_field]}},
        module: module
      })
      when is_atom(coll_field) do
    table_name = module.__naming__().table_name

    """
    create unique_index(:#{table_name}, [:#{name}, :#{coll_field}])
    """
  end

  def down_indexes(_) do
    ""
  end

  def up_indexes(%{attribute: %{name: name, type: :language}, module: module}) do
    table_name = module.__naming__().table_name

    """
    drop index(:#{table_name}, [:#{name}])
    """
  end

  def up_indexes(%{
        attribute: %{name: name, opts: %{unique: [prevent_collision: true]}},
        module: module
      }) do
    table_name = module.__naming__().table_name

    """
    drop unique_index(:#{table_name}, [:#{name}])
    """
  end

  def up_indexes(%{
        attribute: %{name: name, opts: %{unique: [prevent_collision: coll_field]}},
        module: module
      })
      when is_atom(coll_field) do
    table_name = module.__naming__().table_name

    """
    drop unique_index(:#{table_name}, [:#{name}, :#{coll_field}])
    """
  end

  def up_indexes(%{
        attribute: %{name: name, opts: %{unique: true}},
        module: module
      }) do
    table_name = module.__naming__().table_name

    """
    drop unique_index(:#{table_name}, [:#{name}])
    """
  end

  def up_indexes(_attr) do
    ""
  end
end
