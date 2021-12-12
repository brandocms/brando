defmodule Brando.Trait.Focal do
  use Brando.Trait

  def after_save(_entry, %{changes: %{path: _}}, _) do
    require Logger
    Logger.error("== path changed -- leave alone")
    :ok
  end

  def after_save(entry, %{changes: %{focal: _}} = changeset, user) do
    require Logger
    Logger.error("== focal changed -- recreate")
    Logger.error(inspect(changeset.changes, pretty: true))
    Brando.Images.Processing.recreate_sizes_for_image(entry, user)
  end

  def after_save(_, _, _) do
    require Logger
    Logger.error("== fallback -- leave alone")
    :ok
  end
end
