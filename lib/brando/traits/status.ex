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
    entry = Brando.Repo.one(from q in schema, where: q.id == ^id)

    {:ok, updated_entry} =
      entry
      |> Ecto.Changeset.cast(%{status: status}, [:status])
      |> Brando.Repo.update()

    {:ok, identifier_result} = Brando.Content.update_identifier(schema, updated_entry)

    identifier_id =
      case identifier_result do
        %Brando.Content.Identifier{id: id} -> id
        _ -> nil
      end

    Brando.Content.Blocks.enqueue_entry_cascade(schema, updated_entry, identifier_id)
    Brando.Cache.Query.evict({:ok, %{__struct__: schema, id: id}})
  end
end
