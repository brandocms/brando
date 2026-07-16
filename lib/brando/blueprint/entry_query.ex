defmodule Brando.Blueprint.EntryQuery do
  @moduledoc """
  Read-only loading of complete Blueprint entries.

  This boundary keeps rendering and background work independent of the generic
  query module's mutation, revision, pagination, and filtering machinery.
  """

  alias Brando.Blueprint.Preloads

  @doc """
  Gets an entry by ID with every Blueprint-managed association preloaded.

  Soft-deleted entries remain addressable, matching the historical
  `Brando.Query.get_entry/2` behavior used by background render jobs.
  """
  @spec get(module(), integer() | binary()) :: {:ok, struct()} | {:error, term()}
  def get(schema, id) do
    context = schema.__modules__().context
    singular = schema.__naming__().singular

    opts =
      if schema.has_trait(Brando.Trait.SoftDelete) do
        %{matches: %{id: id}, with_deleted: true}
      else
        %{matches: %{id: id}}
      end

    opts = Map.put(opts, :preload, Preloads.for_schema(schema))
    apply(context, :"get_#{singular}", [opts])
  end
end
