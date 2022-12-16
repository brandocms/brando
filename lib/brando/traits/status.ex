defmodule Brando.Trait.Status do
  @moduledoc """
  Adds `deleted_at`
  """
  use Brando.Trait
  import Ecto.Query

  attributes do
    attribute :status, :status, required: true
  end

  def update_status(schema, id, status) do
    query = from q in schema, where: q.id == ^id, update: [set: [status: ^status]]
    Brando.repo().update_all(query, [])
    Brando.Datasource.update_datasource(schema)
    Brando.Cache.Query.evict({:ok, %{__struct__: schema, id: id}})
  end
end
