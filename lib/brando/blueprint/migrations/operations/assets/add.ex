defmodule Brando.Blueprint.Migrations.Operations.Asset.Add do
  # import Brando.Blueprint.Migrations.Types
  @moduledoc false
  defstruct asset: nil,
            module: nil,
            opts: nil

  def up(%{asset: %{type: :image, name: name}}) do
    """
    add #{inspect(name)}_id, references(:images, on_delete: :nilify_all)
    """
  end

  def up(%{asset: %{type: :file, name: name}}) do
    """
    add #{inspect(name)}_id, references(:files, on_delete: :nilify_all)
    """
  end

  def up(%{asset: %{type: :gallery, name: name}}) do
    """
    add #{inspect(name)}_id, references(:galleries, on_delete: :nilify_all)
    """
  end

  def up(%{asset: %{type: :video, name: name}}) do
    """
    add #{inspect(name)}, :jsonb
    """
  end

  def up(%{asset: _}) do
    ""
  end

  def down(%{asset: %{type: :image, name: name}}) do
    """
    remove #{inspect(name)}_id
    """
  end

  def down(%{asset: %{type: :file, name: name}}) do
    """
    remove #{inspect(name)}_id
    """
  end

  def down(%{asset: %{type: :video, name: name}}) do
    """
    remove #{inspect(name)}
    """
  end

  def down(%{asset: %{type: :gallery, name: name}}) do
    """
    remove #{inspect(name)}_id
    """
  end

  def down(%{asset: _}) do
    ""
  end

  def up_indexes(_) do
    ""
  end

  def down_indexes(_) do
    ""
  end
end
