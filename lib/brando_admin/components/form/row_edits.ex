defmodule BrandoAdmin.Components.Form.RowEdits do
  @moduledoc false
  # The edits this editor made to the rows of each embedded list
  # (`embeds_many`) and embedded one, recorded as they make them: the fields
  # they typed in a row, and the rows they added, removed or moved. Rows are
  # named by key (`SubformHelpers.row_key/1`: `id-…` for a saved row, the
  # `_key` of a new one), which field sync carries to the other editors with
  # the row.
  #
  # Another editor's save (`Form.take_saved_entry/1`) keeps exactly these on
  # top of the saved rows (`RelationRows.keep_list/5`, `RelationRows.keep/5`):
  # a value the form holds because another editor sent it is never one of
  # them, and a field another editor sent a value of their own for is theirs
  # from then on (`received/4`). The record lasts from when the form loaded
  # or this editor last saved until this editor saves or discards; shipping
  # a list does not clear it.

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
  "quotes", "1", "text"]`, the row by its key in `entry_params`; `["page",
  "feature", "text"]`, the embedded one the form holds), and the rows the
  event added, removed or moved (a drop or sort param).
  """
  def typed(edits, fields, previous, changeset, target, entry_params) do
    edits =
      Enum.reduce(fields, edits, fn field, edits ->
        if held_rows(previous, field) === held_rows(changeset, field),
          do: edits,
          else: record_rows(edits, field, previous, changeset)
      end)

    with [_singular, name | path] <- List.wrap(target),
         field when not is_nil(field) <- Enum.find(fields, &(Atom.to_string(&1) == name)),
         {key, input} when is_binary(key) <- row_input(changeset, field, path, Map.get(entry_params || %{}, name)),
         row_field when not is_nil(row_field) <- row_field(changeset, field, input) do
      put_typed(edits, field, key, [row_field])
    else
      _ -> edits
    end
  end

  # Compare the raw embed before get_embed wraps stored rows as changesets.
  # The cast can change a second relation too, regardless of the event target.
  defp held_rows(changeset, field), do: Map.get(changeset.changes, field, Map.get(changeset.data, field))

  # The row an input is in, and the input: a list's row by its key in the
  # params, an embedded one as the form holds it.
  defp row_input(%Changeset{data: %schema{}} = changeset, field, path, params) do
    case {schema.__schema__(:embed, field), path, params} do
      {%{cardinality: :many}, [index, input | _], %{} = rows} -> {PendingRows.param_key(rows[index]), input}
      {%{cardinality: :one}, [input | _], _row} -> {one_key(changeset, field), input}
      _ -> nil
    end
  end

  defp one_key(changeset, field) do
    case SubformHelpers.current_entries(changeset, field) do
      [] -> nil
      row -> SubformHelpers.row_key(row)
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
  Another editor's `value` for `field`, the rows they hold: a field this
  editor typed in a row that they hold otherwise is theirs from then on, as
  a field another editor sends is (`Form.received_fields/1`). Their rows
  hold what this editor sent too, so a field they hold as `changeset`, the
  form, does stays this editor's; with `recovered?` (the form holds the
  list as a reconnect recovered it) it is theirs too.
  """
  def received(edits, field, changeset, value, recovered?) do
    list = get(edits, field)
    mine = rows_by_key(changeset, field)

    theirs =
      for row <- List.wrap(value), key = SubformHelpers.row_key(row), is_binary(key), into: %{}, do: {key, applied(row)}

    typed =
      for {key, fields} <- list.typed,
          fields =
            MapSet.reject(fields, &((recovered? and Map.has_key?(theirs, key)) or differs?(mine[key], theirs[key], &1))),
          MapSet.size(fields) > 0,
          into: %{},
          do: {key, fields}

    edits |> Map.put(field, %{list | typed: typed}) |> drop_empty(field)
  end

  defp differs?(%{} = mine, %{} = theirs, field), do: Map.get(mine, field) != Map.get(theirs, field)
  defp differs?(_mine, _theirs, _field), do: false

  defp applied(%Changeset{} = row), do: Changeset.apply_changes(row)
  defp applied(row), do: row

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
