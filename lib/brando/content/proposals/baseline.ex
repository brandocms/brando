defmodule Brando.Content.Proposals.Baseline do
  @moduledoc """
  The entries of an applied proposal as they were before it was applied.

  When `Brando.Content.Proposals.apply/4` saves a proposal, its receipt keeps
  each entry it changed as it loaded it, in `Brando.Drafts.Params.snapshot/1`
  form. `load/2` turns that snapshot back into the entry, with its blocks, so
  an applied or undone proposal is reviewed against the content it was
  applied to. Reviewed against the entry as it is now, each change would show
  again on top of its own result: a copied block twice, a setting's new value
  as its old one, a removed block as "a block".
  """
  import Ecto.Query, only: [from: 2]

  require Logger

  alias Brando.Content.Identifier
  alias Brando.Repo

  @doc """
  The entry as `snapshot` holds it. Without a snapshot, or if it no longer
  loads into the schema, the saved `entry` is used.
  """
  @spec load(struct(), map() | nil) :: struct()
  def load(%schema{} = entry, %{} = snapshot) do
    snapshot |> to_struct(schema) |> with_identifiers()
  rescue
    error ->
      Logger.error(
        "The snapshot of #{inspect(schema)} ##{entry.id} in a proposal receipt could not be loaded: " <>
          Exception.message(error)
      )

      entry
  end

  def load(entry, _snapshot), do: entry

  # Fields and embeds load as from JSON; the associations the snapshot holds,
  # one level at a time.
  defp to_struct(params, schema) do
    loaded = schema |> Ecto.embedded_load(params, :json) |> Ecto.put_meta(state: :loaded)

    Enum.reduce(schema.__schema__(:associations), loaded, fn name, struct ->
      case {schema.__schema__(:association, name), Map.fetch(params, to_string(name))} do
        {%{cardinality: :many, related: related}, {:ok, items}} when is_list(items) ->
          Map.put(struct, name, Enum.map(items, &to_struct(&1, related)))

        {%{related: related}, {:ok, %{} = item}} ->
          Map.put(struct, name, to_struct(item, related))

        _ ->
          struct
      end
    end)
  end

  # A snapshot leaves out the entries that link variables and selections
  # point to; the review names a block by them.
  defp with_identifiers(entry) do
    ids = entry |> identifier_ids([]) |> Enum.uniq()

    identifiers =
      if ids == [],
        do: %{},
        else: Map.new(Repo.all(from(i in Identifier, where: i.id in ^ids)), &{&1.id, &1})

    put_identifiers(entry, identifiers)
  end

  defp identifier_ids(list, acc) when is_list(list), do: Enum.reduce(list, acc, &identifier_ids/2)

  defp identifier_ids(%{__meta__: _} = struct, acc) do
    acc = if links?(struct), do: [struct.identifier_id | acc], else: acc
    struct |> associations() |> Enum.reduce(acc, fn {_name, value}, acc -> identifier_ids(value, acc) end)
  end

  defp identifier_ids(_value, acc), do: acc

  defp put_identifiers(list, identifiers) when is_list(list), do: Enum.map(list, &put_identifiers(&1, identifiers))

  defp put_identifiers(%{__meta__: _} = struct, identifiers) do
    struct = if links?(struct), do: %{struct | identifier: identifiers[struct.identifier_id]}, else: struct

    struct
    |> associations()
    |> Enum.reduce(struct, fn {name, value}, struct -> Map.put(struct, name, put_identifiers(value, identifiers)) end)
  end

  defp put_identifiers(value, _identifiers), do: value

  defp links?(%{identifier_id: id, identifier: %Ecto.Association.NotLoaded{}}) when is_integer(id), do: true
  defp links?(_struct), do: false

  defp associations(%schema{} = struct) do
    for name <- schema.__schema__(:associations),
        value = Map.get(struct, name),
        is_list(value) or (is_map(value) and not is_struct(value, Ecto.Association.NotLoaded)),
        do: {name, value}
  end
end
