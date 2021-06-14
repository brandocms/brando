defmodule Brando.Blueprint.Migrations.Operations.Relation.Add do
  # import Brando.Blueprint.Migrations.Types

  defstruct relation: nil,
            module: nil,
            opts: nil

  def up(%{
        relation: %{type: :belongs_to, name: name, opts: %{module: referenced_module}}
      }) do
    referenced_table = referenced_module.__schema__(:source)
    uuid? = referenced_module.__primary_key__() == {:id, :binary_id, autogenerate: true}

    if uuid? do
      """
      add #{inspect(name)}_id, references(:#{referenced_table}, type: :uuid)
      """
    else
      """
      add #{inspect(name)}_id, references(:#{referenced_table})
      """
    end
  end

  def up(%{
        relation: %{type: :embeds_many, name: name, opts: %{module: _}}
      }) do
    """
    add #{inspect(name)}, :jsonb
    """
  end

  def up(%{
        relation: %{type: :embeds_one, name: name, opts: %{module: _}}
      }) do
    """
    add #{inspect(name)}, :jsonb
    """
  end

  def up(%{relation: _}) do
    ""
  end

  def down(%{
        relation: %{type: :belongs_to, name: name}
      }) do
    """
    remove #{inspect(name)}
    """
  end

  def down(%{
        relation: %{type: :embeds_many, name: name, opts: %{module: _}}
      }) do
    """
    remove #{inspect(name)}
    """
  end

  def down(%{
        relation: %{type: :embeds_one, name: name, opts: %{module: _}}
      }) do
    """
    remove #{inspect(name)}
    """
  end

  def down(%{relation: _}) do
    ""
  end

  def up_indexes(%{
        relation: %{type: :belongs_to, name: name, opts: %{unique: [with: other_field]}},
        module: module
      })
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
end
