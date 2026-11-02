defmodule Brando.Trait.Status do
  @moduledoc """
  Adds a required status field and coordinates status changes with identifiers,
  content cascades, and query cache eviction.
  """
  use Brando.Trait

  alias Brando.Authorization.Boundary
  alias Brando.Trait.Status.Compiler

  import Ecto.Query

  @impl true
  def generate_code(module, config), do: Compiler.generate_code(module, config)

  @doc "Updates an entry's status and synchronizes its identifier, content cascade, and query cache."
  def update_status(schema, id, status, actor \\ nil) do
    actor = actor || Boundary.current_scope()

    if Brando.Authorization.enabled?() do
      schema = Brando.Authorization.Catalog.schema(schema)

      if schema do
        context = schema.__modules__().context
        apply(context, :"update_#{schema.__naming__().singular}", [id, %{status: status}, actor])
      else
        {:error, :forbidden}
      end
    else
      legacy_update_status(schema, id, status, actor)
    end
  end

  defp legacy_update_status(schema, id, status, actor) do
    Boundary.run(actor, :update, schema, fn user ->
      with %{} = entry <- Brando.Repo.one(from q in schema, where: q.id == ^id),
           changeset = Ecto.Changeset.cast(entry, %{status: status}, [:status]),
           :ok <- Boundary.change(user, :update, changeset),
           {:ok, updated_entry} <- Brando.Repo.update(changeset) do
        Brando.Activity.saved(changeset, updated_entry, actor)
        update_status_side_effects(schema, id, updated_entry)
      else
        nil -> {:error, :not_found}
        error -> error
      end
    end)
  end

  defp update_status_side_effects(schema, id, updated_entry) do
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
