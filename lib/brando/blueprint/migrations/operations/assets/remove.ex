defmodule Brando.Blueprint.Migrations.Operations.Asset.Remove do
  defstruct asset: nil,
            module: nil,
            opts: nil

  def down(%{
        asset: %{type: :image, name: name}
      }) do
    """
    add #{inspect(name)}, :jsonb
    """
  end

  def down(%{
        asset: %{type: :file, name: name}
      }) do
    """
    add #{inspect(name)}, :jsonb
    """
  end

  def down(%{
        asset: %{type: :video, name: name}
      }) do
    """
    add #{inspect(name)}, :jsonb
    """
  end

  def down(%{
        asset: %{type: :gallery, name: name}
      }) do
    """
    add #{inspect(name)}, :jsonb
    """
  end

  def down(%{asset: _}) do
    ""
  end

  def up(%{
        asset: %{type: :image, name: name}
      }) do
    """
    remove #{inspect(name)}
    """
  end

  def up(%{
        asset: %{type: :file, name: name}
      }) do
    """
    remove #{inspect(name)}
    """
  end

  def up(%{
        asset: %{type: :video, name: name}
      }) do
    """
    remove #{inspect(name)}
    """
  end

  def up(%{
        asset: %{type: :gallery, name: name}
      }) do
    """
    remove #{inspect(name)}
    """
  end

  def up(%{asset: _}) do
    ""
  end

  def up_indexes(_) do
    ""
  end

  def down_indexes(_) do
    ""
  end
end
