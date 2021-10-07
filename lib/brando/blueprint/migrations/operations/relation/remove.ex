defmodule Brando.Blueprint.Migrations.Operations.Relation.Remove do
  # import Brando.Blueprint.Migrations.Types

  defstruct relation: nil,
            module: nil,
            opts: nil

  def down(%{
        relation: %{type: :belongs_to, name: name, opts: %{module: referenced_module}}
      }) do
    referenced_table = referenced_module.__schema__(:source)

    """
    add #{inspect(name)}_id, references(:#{referenced_table})
    """
  end

  def down(%{
        relation: %{type: :image, name: name}
      }) do
    """
    add #{inspect(name)}, :jsonb
    """
  end

  def down(%{
        relation: %{type: :embeds_many, name: name, opts: %{module: _}}
      }) do
    """
    add #{inspect(name)}, :jsonb
    """
  end

  def down(%{
        relation: %{type: :embeds_one, name: name, opts: %{module: _}}
      }) do
    """
    add #{inspect(name)}, :jsonb
    """
  end

  def down(%{relation: _}) do
    ""
  end

  def up(%{
        relation: %{type: :belongs_to, name: name}
      }) do
    """
    remove #{inspect(name)}_id
    """
  end

  def up(%{
        relation: %{type: :image, name: name}
      }) do
    """
    remove #{inspect(name)}
    """
  end

  def up(%{
        relation: %{type: :embeds_many, name: name, opts: %{module: _}}
      }) do
    """
    remove #{inspect(name)}
    """
  end

  def up(%{
        relation: %{type: :embeds_one, name: name, opts: %{module: _}}
      }) do
    """
    remove #{inspect(name)}
    """
  end

  def up(%{relation: _}) do
    ""
  end

  def up_indexes(_) do
    ""
  end

  def down_indexes(_) do
    ""
  end
end
