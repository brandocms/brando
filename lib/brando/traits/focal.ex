defmodule Brando.Trait.Focal do
  use Brando.Trait

  def after_save(_entry, %{changes: %{path: _}}, _) do
    :ok
  end

  def after_save(entry, %{changes: %{focal: _}}, user) do
    Brando.Images.Processing.recreate_sizes_for_image(entry, user)
  end

  def after_save(_, _, _) do
    :ok
  end
end
