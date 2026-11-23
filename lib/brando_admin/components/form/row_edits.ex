defmodule BrandoAdmin.Components.Form.RowEdits do
  @moduledoc false
  # The edits this editor made to the rows of each embedded list
  # (`embeds_many`), recorded as they make them: the fields they typed in a
  # row, and the rows they added, removed or moved. Rows are named by key
  # (`SubformHelpers.row_key/1`: `id-…` for a saved row, the `_key` of a new
  # one), which field sync carries to the other editors with the row.
  #
  # Another editor's save (`Form.take_saved_entry/1`) keeps exactly these on
  # top of the saved rows (`RelationRows.keep_list/5`): a value the form holds
  # because another editor sent it is never one of them. The record lasts
  # from when the form loaded or this editor last saved until this editor
  # saves or discards; shipping a list does not clear it.

  alias BrandoAdmin.Components.Form.Input.SubformHelpers
  alias BrandoAdmin.Components.Form.PendingRows
  alias Ecto.Changeset

  @type list_edits :: %{
          typed: %{String.t() => MapSet.t(atom())},
          added: MapSet.t(String.t()),
          removed: MapSet.t(String.t()),
          moved?: boolean()
        }
  @type t :: %{atom() => list_edits()}

  def empty, do: %{typed: %{}, added: MapSet.new(), removed: MapSet.new(), moved?: false}

  @doc "The edits to `field`'s rows."
  def get(edits, field), do: Map.get(edits, field, empty())

  @doc "Whether this editor changed anything in `field`'s rows."
  def any?(edits, field), do: get(edits, field) != empty()

  @doc """
  A `validate`: the field of the row its `_target` names (`["page",
  "quotes", "1", "text"]`, the row by its key in `entry_params`), and the
  rows the event added, removed or moved (a drop or sort param).
  """
  def typed(edits, fields, previous, changeset, target, entry_params) do
    edits = Enum.reduce(fields, edits, &record_rows(&2, &1, previous, changeset))

    with [_singular, name, index, row_field | _] <- List.wrap(target),
         field when not is_nil(field) <- Enum.find(fields, &(Atom.to_string(&1) == name)),
         %{} = row <- get_in(entry_params || %{}, [name, index]),
         key when is_binary(key) <- PendingRows.param_key(row),
         row_field when not is_nil(row_field) <- row_field(changeset, field, row_field) do
      put_typed(edits, field, key, [row_field])
    else
      _ -> edits
    end
  end

  @doc """
  A change the form made itself (a row added, an asset put in a row, a
  recovered form): every row it added, removed or moved, and every field it
  changed in a row both hold.
  """
  def changed(edits, fields, previous, changeset) do
    Enum.reduce(fields, edits, fn field, edits ->
      before = rows_by_key(previous, field)

      typed =
        for {key, row} <- rows_by_key(changeset, field),
            %{} = was <- [Map.get(before, key)],
            changed = changed_fields(was, row),
            changed != [],
            do: {key, changed}

      edits
      |> record_rows(field, previous, changeset)
      |> then(&Enum.reduce(typed, &1, fn {key, changed}, edits -> put_typed(edits, field, key, changed) end))
    end)
  end

  @doc """
  Renames rows after a merge (`RelationRows.keep_list/5`): a new row the
  save wrote goes by its saved key (`id-…`), and is no longer one this
  editor added.
  """
  def rename(edits, field, renamed) do
    %{typed: typed, added: added, removed: removed} = list = get(edits, field)
    name = &Map.get(renamed, &1, &1)

    list = %{
      list
      | typed: Map.new(typed, fn {key, fields} -> {name.(key), fields} end),
        added: added |> Enum.reject(&Map.has_key?(renamed, &1)) |> MapSet.new(),
        removed: MapSet.new(removed, name)
    }

    edits |> Map.put(field, list) |> drop_empty(field)
  end

  defp drop_empty(edits, field), do: if(edits[field] == empty(), do: Map.delete(edits, field), else: edits)

  defp record_rows(edits, field, previous, changeset) do
    before = keys(previous, field)
    now = keys(changeset, field)

    if before == now do
      edits
    else
      {before_set, now_set} = {MapSet.new(before), MapSet.new(now)}
      %{added: added, removed: removed, moved?: moved?} = list = get(edits, field)
      common = &(MapSet.member?(before_set, &1) and MapSet.member?(now_set, &1))

      Map.put(edits, field, %{
        list
        | added: added |> MapSet.union(MapSet.difference(now_set, before_set)) |> MapSet.intersection(now_set),
          removed: MapSet.union(removed, MapSet.difference(before_set, now_set)),
          moved?: moved? or Enum.filter(before, common) != Enum.filter(now, common)
      })
    end
  end

  defp put_typed(edits, field, key, fields) do
    list = get(edits, field)
    typed = Map.update(list.typed, key, MapSet.new(fields), &MapSet.union(&1, MapSet.new(fields)))
    Map.put(edits, field, %{list | typed: typed})
  end

  defp keys(changeset, field),
    do: changeset |> SubformHelpers.row_keys(field) |> Enum.reject(&is_nil/1)

  defp rows_by_key(changeset, field) do
    for row <- List.wrap(SubformHelpers.current_entries(changeset, field)),
        key = SubformHelpers.row_key(row),
        is_binary(key),
        into: %{},
        do: {key, Changeset.apply_changes(row)}
  end

  defp changed_fields(%row_schema{} = was, row) do
    for field <- row_fields(row_schema), Map.get(was, field) != Map.get(row, field), do: field
  end

  defp row_fields(row_schema), do: row_schema.__schema__(:fields) -- row_schema.__schema__(:primary_key)

  defp row_field(%Changeset{data: %schema{}}, field, name) do
    %{related: related} = schema.__schema__(:embed, field)
    Enum.find(row_fields(related), &(Atom.to_string(&1) == name))
  end
end
