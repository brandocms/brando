defmodule BrandoAdmin.Components.Form.PendingRows do
  @moduledoc """
  Rows the server has added or removed that the browser has not shown yet.

  The browser sends a nested relation's whole list with every change and
  Save, by position, and Ecto casts it as it is (`sort_param`, `drop_param`).
  That is right as long as the list is the one the browser last received.
  Between an add or a removal and its patch, it is not: a change serialized
  in that window lists the rows as they were, so a removed row came back, or
  an added one was lost (#3157).

  So the Form remembers, by row key (`SubformHelpers.row_key/1`), what
  happened in that window, and corrects only that in the next params before
  the cast:

    * a row removed since (by an operation, or by the browser's own drop
      param) is taken out of the params, with its sort and drop entries;
    * a row added since (by an operation) that the params don't list is put
      in, with its values, where the server placed it.

  Everything else is Ecto's as before: the order from the sort param, rows
  the params add or drop, validation and sequencing. An entry is settled once
  a submission shows the browser has caught up: a removed row it no longer
  lists, an added row it lists. Recovery after a reconnect resets them, as
  the browser's rows are then the ones to keep.
  """

  alias BrandoAdmin.Components.Form.Input.SubformHelpers
  alias Ecto.Changeset

  @type t :: %{optional(atom()) => %{removed: MapSet.t(String.t()), added: MapSet.t(String.t())}}

  @doc "Records an operation on `field` from the row keys before and after it."
  @spec record(t(), atom(), [String.t() | nil], [String.t() | nil]) :: t()
  def record(pending, field, before_keys, after_keys) do
    before_keys = keys(before_keys)
    after_keys = keys(after_keys)
    %{removed: removed, added: added} = Map.get(pending, field, empty())

    Map.put(pending, field, %{
      removed: removed |> MapSet.union(MapSet.difference(before_keys, after_keys)) |> MapSet.difference(after_keys),
      added: added |> MapSet.union(MapSet.difference(after_keys, before_keys)) |> MapSet.intersection(after_keys)
    })
  end

  @doc """
  Corrects `entry_params` for what the browser has not seen, against
  `current`, the form's latest changeset. Returns the params and, for each
  relation whose rows carry keys, the keys the browser listed (for `settle/3`).
  """
  @spec correct(map() | nil, t(), Changeset.t()) :: {map() | nil, %{atom() => MapSet.t(String.t())}}
  def correct(entry_params, pending, %Changeset{data: %module{}} = current) when is_map(entry_params) do
    Enum.reduce(relations(module), {entry_params, %{}}, fn field, {params, seen} ->
      case Map.fetch(params, Atom.to_string(field)) do
        {:ok, rows} -> correct_relation(params, seen, module, field, rows, pending, current)
        :error -> {params, seen}
      end
    end)
  end

  def correct(entry_params, _pending, _current), do: {entry_params, %{}}

  defp correct_relation(params, seen, module, field, rows, pending, current) do
    rows = if is_map(rows), do: rows, else: %{}
    listed = rows |> Map.values() |> Enum.map(&param_key/1) |> Enum.reject(&is_nil/1) |> MapSet.new()
    seen = if MapSet.size(listed) > 0 or Map.has_key?(pending, field), do: Map.put(seen, field, listed), else: seen

    case Map.fetch(pending, field) do
      {:ok, field_pending} -> {correct_field(params, module, field, rows, field_pending, current), seen}
      :error -> {params, seen}
    end
  end

  @doc """
  Settles `pending` after a cast: `seen` is what the browser listed
  (`correct/3`), `changeset` the result. A row the browser listed that the
  result lacks (its drop param, or a removal it hadn't seen) stays removed
  until the browser stops listing it.
  """
  @spec settle(t(), %{atom() => MapSet.t(String.t())}, Changeset.t()) :: t()
  def settle(pending, seen, %Changeset{} = changeset) do
    Enum.reduce(seen, pending, fn {field, listed}, pending ->
      result = keys(SubformHelpers.row_keys(changeset, field))
      %{removed: removed, added: added} = Map.get(pending, field, empty())

      settled = %{
        removed: removed |> MapSet.intersection(listed) |> MapSet.union(MapSet.difference(listed, result)),
        added: added |> MapSet.intersection(result) |> MapSet.difference(listed)
      }

      if settled == empty(), do: Map.delete(pending, field), else: Map.put(pending, field, settled)
    end)
  end

  defp key_sort(key) do
    case Integer.parse(key) do
      {n, ""} -> {0, n}
      _ -> {1, key}
    end
  end

  defp correct_field(params, module, field, rows, %{removed: removed, added: added}, current) do
    server_rows = SubformHelpers.current_entries(current, field)
    server_keys = Enum.map(server_rows, &SubformHelpers.row_key/1)
    # Only what the server still says: a later change may have settled it
    removed = MapSet.difference(removed, keys(server_keys))
    sort_name = param_name(module, field, :sort_param)
    drop_name = param_name(module, field, :drop_param)

    stale = for {index, row} <- rows, MapSet.member?(removed, param_key(row)), do: index
    rows = Map.drop(rows, stale)
    # A list sent without a sort param (PageVars, Globals) is in Ecto's key
    # order; spell that out, so a row put in lands where the server has it.
    sort =
      case Map.get(params, sort_name) do
        sort when is_list(sort) -> Enum.reject(sort, &(&1 in stale))
        _ -> rows |> Map.keys() |> Enum.sort_by(&key_sort/1)
      end

    drop = params |> Map.get(drop_name) |> List.wrap() |> Enum.reject(&(&1 in stale))

    listed = rows |> Map.values() |> Enum.map(&param_key/1) |> MapSet.new()

    {rows, sort} =
      server_rows
      |> Enum.with_index()
      |> Enum.reduce({rows, sort}, fn {row, position}, {rows, sort} ->
        key = SubformHelpers.row_key(row)

        if MapSet.member?(added, key) and not MapSet.member?(listed, key) do
          index = next_index(rows)
          after_index = preceding_index(rows, server_keys, position)
          {Map.put(rows, index, row_params(row, key)), insert_after(sort, after_index, index)}
        else
          {rows, sort}
        end
      end)

    params
    |> Map.put(Atom.to_string(field), rows)
    |> put_list(sort_name, sort)
    |> put_list(drop_name, drop)
  end

  # The browser's row: a saved row by its id, a new one by its `_key`.
  defp param_key(%{"id" => id}) when is_binary(id) and id != "", do: "id-" <> id
  defp param_key(%{"_key" => key}) when is_binary(key) and key != "", do: key
  defp param_key(_row), do: nil

  # The params index of the nearest row above `position` that the params list.
  defp preceding_index(rows, server_keys, position) do
    by_key = Map.new(rows, fn {index, row} -> {param_key(row), index} end)

    server_keys
    |> Enum.take(position)
    |> Enum.reverse()
    |> Enum.find_value(&Map.get(by_key, &1))
  end

  defp insert_after([], _after_index, index), do: [index]
  defp insert_after(sort, nil, index), do: [index | sort]

  defp insert_after(sort, after_index, index) do
    case Enum.find_index(sort, &(&1 == after_index)) do
      nil -> sort ++ [index]
      at -> List.insert_at(sort, at + 1, index)
    end
  end

  defp next_index(rows) do
    max =
      rows
      |> Map.keys()
      |> Enum.map(&Integer.parse/1)
      |> Enum.map(fn
        {n, _} -> n
        :error -> -1
      end)
      |> Enum.max(fn -> -1 end)

    Integer.to_string(max + 1)
  end

  # The values the browser would have sent for a row it has not drawn yet:
  # the row as the server holds it, nested embeds and associations included
  # (a new menu item's default link), and its key.
  defp row_params(row, key) do
    entry = if match?(%Changeset{}, row), do: Changeset.apply_changes(row), else: row
    params = entry |> to_params() |> Map.delete("id")

    case key do
      "id-" <> id -> Map.put(params, "id", id)
      key -> Map.put(params, "_key", key)
    end
  end

  defp to_params(%module{} = struct) do
    nested = module.__schema__(:embeds) ++ module.__schema__(:associations)
    fields = module.__schema__(:fields) -- (nested ++ [:inserted_at, :updated_at])

    params =
      Enum.reduce(fields, %{}, fn field, params ->
        case Map.get(struct, field) do
          nil -> params
          value -> Map.put(params, Atom.to_string(field), value)
        end
      end)

    Enum.reduce(nested, params, fn field, params ->
      case nested_params(module, field, Map.get(struct, field)) do
        nil -> params
        value -> Map.put(params, Atom.to_string(field), value)
      end
    end)
  end

  defp nested_params(module, field, value) do
    cond do
      match?(%Ecto.Association.NotLoaded{}, value) or is_nil(value) -> nil
      match?(%Ecto.Association.BelongsTo{}, module.__schema__(:association, field)) -> nil
      match?(%Ecto.Association.HasThrough{}, module.__schema__(:association, field)) -> nil
      is_list(value) -> value |> Enum.with_index() |> Map.new(fn {item, i} -> {Integer.to_string(i), to_params(item)} end)
      is_struct(value) -> to_params(value)
      true -> nil
    end
  end

  # An empty list goes: a sort entry left for a row taken out would make Ecto
  # add an empty row in its place.
  defp put_list(params, name, []), do: Map.delete(params, name)
  defp put_list(params, name, list), do: Map.put(params, name, list)

  defp relations(module) do
    Enum.filter(module.__schema__(:associations) ++ module.__schema__(:embeds), fn field ->
      case module.__schema__(:association, field) || module.__schema__(:embed, field) do
        %{cardinality: :many} -> true
        _ -> false
      end
    end)
  end

  defp param_name(module, field, kind) do
    # Plain embedded schemas have no Blueprint relations, and default names
    opts =
      with true <- function_exported?(module, :__naming__, 0),
           %{opts: opts} when is_map(opts) <- Brando.Blueprint.Relations.__relation__(module, field) do
        opts
      else
        _ -> %{}
      end

    opts |> Map.get(kind, :"#{kind |> to_string() |> String.replace("_param", "")}_#{field}_ids") |> to_string()
  end

  defp keys(list), do: list |> Enum.reject(&is_nil/1) |> MapSet.new()
  defp empty, do: %{removed: MapSet.new(), added: MapSet.new()}
end
