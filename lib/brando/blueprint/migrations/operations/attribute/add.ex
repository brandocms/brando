defmodule Brando.Blueprint.Migrations.Operations.Attribute.Add do
  import Brando.Blueprint.Migrations.Types

  defstruct attribute: nil,
            module: nil

  def up(%{attribute: %{name: :inserted_at}}) do
    """
    timestamps()
    """
  end

  def up(%{attribute: %{name: :updated_at}}), do: ""

  def up(%{attribute: attr}) do
    """
    add #{inspect(attr.name)}, #{inspect(migration_type(attr.type))}
    """
  end

  def down(%{attribute: attr}) do
    """
    remove #{inspect(attr.name)}
    """
  end

  def up_indexes(%{attribute: %{name: name, type: :language, opts: opts}, module: module}) do
    table_name = module.__naming__().table_name

    """
    create index(:#{table_name}, [:#{name}])
    """
  end

  def up_indexes(%{
        attribute: %{name: name, opts: %{unique: [prevent_collision: true]}},
        module: module
      }) do
    table_name = module.__naming__().table_name

    """
    create unique_index(:#{table_name}, [:#{name}])
    """
  end

  def up_indexes(%{
        attribute: %{name: name, opts: %{unique: true}},
        module: module
      }) do
    table_name = module.__naming__().table_name

    """
    create unique_index(:#{table_name}, [:#{name}])
    """
  end

  def up_indexes(%{
        attribute: %{name: name, opts: %{unique: [with: other_field]}},
        module: module
      })
      when is_atom(other_field) do
    table_name = module.__naming__().table_name

    """
    create unique_index(:#{table_name}, [:#{name}, :#{other_field}])
    """
  end

  def up_indexes(%{
        attribute: %{name: name, opts: %{unique: [prevent_collision: coll_field]}},
        module: module
      })
      when is_atom(coll_field) do
    table_name = module.__naming__().table_name

    """
    create unique_index(:#{table_name}, [:#{name}, :#{coll_field}])
    """
  end

  def up_indexes(_) do
    ""
  end

  def down_indexes(%{attribute: %{name: name, type: :language}, module: module}) do
    table_name = module.__naming__().table_name

    """
    drop index(:#{table_name}, [:#{name}])
    """
  end

  def down_indexes(%{
        attribute: %{name: name, opts: %{unique: [prevent_collision: true]}},
        module: module
      }) do
    table_name = module.__naming__().table_name

    """
    drop unique_index(:#{table_name}, [:#{name}])
    """
  end

  def down_indexes(%{
        attribute: %{name: name, opts: %{unique: [prevent_collision: coll_field]}},
        module: module
      })
      when is_atom(coll_field) do
    table_name = module.__naming__().table_name

    """
    drop unique_index(:#{table_name}, [:#{name}, :#{coll_field}])
    """
  end

  def down_indexes(%{
        attribute: %{name: name, opts: %{unique: true}},
        module: module
      }) do
    table_name = module.__naming__().table_name

    """
    drop unique_index(:#{table_name}, [:#{name}])
    """
  end

  def down_indexes(attr) do
    ""
  end
end
