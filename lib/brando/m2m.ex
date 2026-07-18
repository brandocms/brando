defmodule Brando.M2M do
  @moduledoc """
  Provides many_to_many helpers for Ecto Changesets.

  The following example schema demonstrates how you would configure the
  functionality of our examples below.

  ## Example Schema

      schema "models" do
        many_to_many :tags, App.Tag,
          join_through: App.TagToModel,
          on_delete: :delete_all,
          on_replace: :delete
      end
  """

  import Ecto.Changeset, only: [add_error: 4, cast_assoc: 3, change: 1, put_assoc: 3]
  import Ecto.Query

  alias Ecto.Changeset

  @type id :: integer() | String.t()
  @type lookup :: ([id()] -> [struct()])

  @doc ~S"""
  Cast a collection of IDs into a many_to_many association.

  This function assumes:

    - The column on your associated table is called `id`.

  ## Example

      def changeset(struct, params \\ %{}) do
        struct
        |> cast(params, ~w())
        |> Brando.M2M.cast_collection(:tags, App.Repo, App.Tag, false)
      end
  """
  @spec cast_collection(Changeset.t(), atom(), module(), module(), boolean()) :: Changeset.t()
  def cast_collection(set, assoc, repo, mod, required) do
    perform_cast(set, assoc, &all(&1, repo, mod), required)
  end

  @doc ~S"""
  Cast a collection of IDs into a many_to_many association using a custom lookup
  function.

  String- and atom-keyed params are accepted. Blank ID sentinels are removed;
  malformed ID collections and unresolved IDs add a changeset error rather than
  being ignored or raising. A required collection must resolve at least one ID.

  Your custom lookup function is expected to receive a list of `ids`, and should
  return one record for every distinct ID.
  The custom lookup function is the perfect place to re-map the list of `ids`,
  such as casting each to Integer.

  ## Example

      def changeset(struct, params \\ %{}) do
        struct
        |> cast(params, ~w())
        |> Brando.M2M.cast_collection(:tags, fn ids ->
          # Convert Strings back to Integers
          ids = Enum.map(ids, &String.to_integer/1)
          App.Repo.all(from t in App.Tag, where: t.id in ^ids)
        end, false),
      end
  """
  @spec cast_collection(Changeset.t(), atom(), lookup(), boolean()) :: Changeset.t()
  def cast_collection(set, assoc, lookup_fn, required) when is_function(lookup_fn) do
    perform_cast(set, assoc, lookup_fn, required)
  end

  defp all(ids, repo, mod) do
    repo.all(from m in mod, where: m.id in ^ids)
  end

  defp perform_cast(set, assoc, lookup_fn, required) do
    case fetch_param(set.params, assoc) do
      {:ok, ids} ->
        cast_ids(set, assoc, ids, lookup_fn, required)

      :error ->
        if required, do: cast_assoc(set, assoc, required: true), else: set
    end
  end

  defp fetch_param(params, assoc) when is_map(params) do
    string_assoc = to_string(assoc)

    cond do
      Map.has_key?(params, string_assoc) -> {:ok, Map.get(params, string_assoc)}
      Map.has_key?(params, assoc) -> {:ok, Map.get(params, assoc)}
      true -> :error
    end
  end

  defp fetch_param(_params, _assoc), do: :error

  defp cast_ids(set, assoc, ids, lookup_fn, required) do
    case normalize_ids(ids) do
      {:ok, []} when required ->
        add_error(set, assoc, "can't be blank", validation: :required)

      {:ok, normalized_ids} ->
        records = lookup_fn.(normalized_ids)
        put_resolved_records(set, assoc, normalized_ids, records)

      :error ->
        add_error(set, assoc, "is invalid", validation: :cast)
    end
  end

  defp put_resolved_records(set, assoc, ids, records) when is_list(records) do
    if length(records) == length(ids) do
      put_assoc(set, assoc, Enum.map(records, &change/1))
    else
      add_error(set, assoc, "is invalid", validation: :cast)
    end
  end

  defp put_resolved_records(set, assoc, _ids, _records) do
    add_error(set, assoc, "is invalid", validation: :cast)
  end

  defp normalize_ids(ids) when ids in [nil, ""], do: {:ok, []}

  defp normalize_ids(ids) when is_list(ids) do
    normalized_ids = ids |> Enum.reject(&(&1 in ["", nil])) |> Enum.uniq()

    if Enum.all?(normalized_ids, &(is_binary(&1) or is_integer(&1))) do
      {:ok, normalized_ids}
    else
      :error
    end
  end

  defp normalize_ids(_ids), do: :error
end
