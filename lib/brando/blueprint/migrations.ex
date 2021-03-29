defmodule Brando.Blueprint.Migrations do
  alias Brando.Blueprint.Snapshot

  def build_migration(module) do
    current_snapshot = Snapshot.build_snapshot(module)
    previous_snapshot = Snapshot.get_latest_snapshot(module)

    {attributes_to_add, attributes_to_remove} = diff(current_snapshot, previous_snapshot)
    require Logger
    Logger.error(inspect(attributes_to_add, pretty: true))
    Logger.error(inspect(attributes_to_remove, pretty: true))
  end

  def diff(current_snapshot, nil) do
    attributes_to_add = current_snapshot.attributes
    {attributes_to_add, []}
  end

  def diff(current_snapshot, previous_snapshot) do
    attributes_to_add =
      Enum.reject(current_snapshot.attributes, fn attribute ->
        Enum.find(previous_snapshot.attributes, &(&1.name == attribute.name))
      end)

    attributes_to_remove =
      Enum.reject(previous_snapshot.attributes, fn attribute ->
        Enum.find(current_snapshot.attributes, &(&1.name == attribute.name))
      end)

    {attributes_to_add, attributes_to_remove}
  end
end
