defmodule Brando.Trait.Status do
  @moduledoc """
  Adds `deleted_at`
  """
  use Brando.Trait
  import Ecto.Query

  def generate_code(_, _) do
    quote do
      attributes do
        attribute :status, :status, required: true
      end
    end
  end

  def update_status(schema, id, status) do
    entry = Brando.repo().one(from q in schema, where: q.id == ^id)

    {:ok, updated_entry} =
      entry
      |> Ecto.Changeset.cast(%{status: status}, [:status])
      |> Brando.repo().update()

    Brando.Datasource.update_datasource(schema)
    Brando.Content.update_identifier(schema, updated_entry)
    Brando.Cache.Query.evict({:ok, %{__struct__: schema, id: id}})
  end
end
