defmodule Brando.Trait.Status do
  @moduledoc """
  Adds a required status field and coordinates status changes with identifiers,
  content cascades, and query cache eviction.
  """
  use Brando.Trait

  alias Brando.Trait.Status.Compiler

  import Ecto.Query

  @impl true
  def generate_code(module, config), do: Compiler.generate_code(module, config)

  @doc "Updates an entry's status and synchronizes its identifier, content cascade, and query cache."
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
