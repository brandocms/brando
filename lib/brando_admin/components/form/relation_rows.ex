defmodule BrandoAdmin.Components.Form.RelationRows do
  @moduledoc false
  # The has_many, has_one and many_to_many relations of an entry form. They
  # don't ship between editors as field changes (`Form.sync_fields/1`), so
  # another editor's save (`Form.take_saved_entry/1`) is where they meet: a
  # relation this editor changed keeps its rows (`keep/3`), and every other
  # relation takes the saved rows. Both changing one relation is a conflict
  # the editor settles (`Form` "Saves by other editors"); the rows are never
  # merged. Rows compare by content (`rows/2`): the rows a form builds again
  # from the browser's params are new structs.

  alias BrandoAdmin.Components.Form.Input.SubformHelpers
  alias Ecto.Association
  alias Ecto.Changeset

  def fields(schema, skip) do
    for name <- schema.__schema__(:associations),
        name not in skip,
        relation?(schema.__schema__(:association, name)),
        do: name
  end

  def relation?(%Changeset{data: %schema{}}, field), do: relation?(schema.__schema__(:association, field))

  defp relation?(%Association.Has{}), do: true
  defp relation?(%Association.ManyToMany{}), do: true
  defp relation?(_assoc), do: false

  @doc """
  A relation's rows without their keys and timestamps, so the saved rows and
  the rows a form built for the same choices compare equal. The relations
  in a row (a multi-select in a subform row) are part of its content. Rows
  removed (or marked to be) are left out; a many_to_many row is the entry it
  names.
  """
  def rows(changeset, field), do: rows(changeset, field, & &1)

  # `order` puts each list of rows, a row's own relations' too, in order.
  defp rows(%Changeset{data: %schema{}} = changeset, field, order) do
    case shown(changeset, field) do
      %Association.NotLoaded{} -> :not_loaded
      rows -> content(schema.__schema__(:association, field), rows, order)
    end
  end

  # The relation as the changeset shows it, its changes applied.
  defp shown(changeset, field) do
    case Map.fetch(changeset.changes, field) do
      {:ok, rows} when is_list(rows) ->
        for %Changeset{action: action} = row <- rows, action not in [:replace, :delete], do: Changeset.apply_changes(row)

      {:ok, %Changeset{action: action}} when action in [:replace, :delete] ->
        nil

      {:ok, %Changeset{} = row} ->
        Changeset.apply_changes(row)

      {:ok, nil} ->
        nil

      :error ->
        Map.get(changeset.data, field)
    end
  end

  defp content(assoc, rows, order),
    do: order.(for row <- List.wrap(rows), not marked_as_deleted?(row), do: row_content(assoc, row, order))

  defp row_content(%Association.ManyToMany{}, row, _order), do: Ecto.primary_key(row)

  defp row_content(%{related_key: owner_key}, %row_schema{} = row, order) do
    skip = [owner_key, :inserted_at, :updated_at | row_schema.__schema__(:primary_key)]
    values = Map.take(row, row_schema.__schema__(:fields) -- skip)

    for name <- fields(row_schema, []),
        Ecto.assoc_loaded?(Map.get(row, name)),
        into: values,
        do: {name, content(row_schema.__schema__(:association, name), Map.get(row, name), order)}
  end

  defp marked_as_deleted?(row), do: Map.get(row, :marked_as_deleted) == true

  @doc """
  A digest of a relation's rows (`rows/2`) in `entry`, the base a form was
  built on, for recovery to tell whether the rows were saved otherwise
  since (`Form.settle_edit/4`). The order the rows were read in is not
  part of it, in the rows' own relations neither (a `sequence` field
  is). `nil` when the entry didn't load the relation.
  """
  def base(%_{} = entry, field) do
    case rows(Changeset.change(entry), field, &Enum.sort/1) do
      :not_loaded -> nil
      rows -> rows |> Brando.Drafts.checksum() |> binary_part(0, 16)
    end
  end

  @doc """
  The relations in `taken` (field => the form revision that replaced their
  rows) that `params` show as they were before: their form revision
  (`_form_rev`) is older.
  """
  def stale(taken, params) do
    case Integer.parse(to_string(params["_form_rev"])) do
      {rev, ""} -> for {field, taken_at} <- taken, rev < taken_at, do: field
      _ -> []
    end
  end

  @doc """
  Whether a row of the relation holds an edit that didn't cast: its rows
  (`rows/2`) don't show it.
  """
  def invalid?(%Changeset{changes: changes}, field) do
    case Map.get(changes, field) do
      rows when is_list(rows) -> Enum.any?(rows, &match?(%Changeset{valid?: false}, &1))
      row -> match?(%Changeset{valid?: false}, row)
    end
  end

  @doc """
  The relation of `saved` as `previous`, the form the editor had, holds it:
  its rows, added rows and removals stay. A row the editor changed keeps its
  changes over the saved row's values, and a row it didn't change is the
  saved row. A row's changes are in its changeset, or in its data when the
  form applied them there (an asset delivery,
  `Form.commit_entry_field_asset/5`): what it holds otherwise than `base`,
  the entry the form was built on. A row it holds that the save removed is a new row, if the
  editor changed it, and gone otherwise. The rows the save added are not
  kept, unless the relation can't replace a row (`on_replace: :raise`).
  """
  def keep(%Changeset{data: %schema{} = data} = saved, %Changeset{} = previous, base, field) do
    assoc = schema.__schema__(:association, field)
    current = Map.get(data, field)
    base = if is_map(base), do: Map.get(base, field)
    base = if Ecto.assoc_loaded?(base), do: base, else: nil

    cond do
      not Ecto.assoc_loaded?(current) ->
        keep_unloaded(saved, previous, field)

      assoc.cardinality == :one ->
        put_kept(saved, field, keep_one(assoc, current, as_change(held(previous, field), base)))

      true ->
        put_kept(
          saved,
          field,
          keep_many(assoc, current, Enum.map(List.wrap(held(previous, field)), &as_change(&1, base)))
        )
    end
  end

  # A row of the form's data the form changed itself: its changes against
  # the row in `base`.
  defp as_change(%_{__meta__: _} = row, base) do
    key = Ecto.primary_key(row)

    case Enum.find(List.wrap(base), &(Ecto.primary_key(&1) == key)) do
      nil ->
        row

      before ->
        if edits(row, before) == %{},
          do: row,
          else: before |> Changeset.change(edits(row, before)) |> Map.put(:action, :update)
    end
  end

  defp as_change(row, _base), do: row

  defp edits(%row_schema{} = row, before) do
    skip = [:inserted_at, :updated_at, :marked_as_deleted | row_schema.__schema__(:primary_key)]

    for field <- row_schema.__schema__(:fields) -- skip,
        Map.get(row, field) != Map.get(before, field),
        into: %{},
        do: {field, Map.get(row, field)}
  end

  # The saved entry didn't load the relation: the form's change goes as is.
  defp keep_unloaded(saved, previous, field) do
    case Map.fetch(previous.changes, field) do
      {:ok, edit} -> %{saved | changes: Map.put(saved.changes, field, edit)}
      :error -> saved
    end
  end

  defp put_kept(changeset, _field, :keep), do: changeset
  defp put_kept(changeset, field, value), do: Changeset.put_assoc(changeset, field, value)

  # The rows the form holds: changesets from its changes, or the structs in
  # its data. In a list, a row the editor took out (`:delete`, a
  # multi-select's unpick) stays, as the editor's intent; one put_assoc
  # replaced does not.
  defp held(%Changeset{} = changeset, field) do
    case Map.fetch(changeset.changes, field) do
      {:ok, rows} when is_list(rows) -> Enum.reject(rows, &match?(%Changeset{action: :replace}, &1))
      {:ok, row} -> if removed?(row), do: nil, else: row
      :error -> Map.get(changeset.data, field)
    end
  end

  defp removed?(%Changeset{action: action}), do: action in [:replace, :delete]
  defp removed?(_row), do: false

  defp applied(%Changeset{} = row), do: Changeset.apply_changes(row)
  defp applied(row), do: row

  defp new?(row), do: Enum.all?(Ecto.primary_key(row), fn {_key, value} -> is_nil(value) end)

  defp by_key(rows), do: Map.new(rows, &{Ecto.primary_key(&1), &1})

  defp keep_many(%Association.ManyToMany{} = assoc, saved, held) do
    linked = for entry <- List.wrap(held), not removed?(entry), do: applied(entry)
    linked ++ unreplaceable(assoc, saved, linked)
  end

  defp keep_many(assoc, saved, held) do
    saved_rows = by_key(saved)
    rows = for entry <- List.wrap(held), row = keep_row(entry, saved_rows), do: row
    rows ++ unreplaceable(assoc, saved, rows)
  end

  # The saved rows a relation that can't replace a row has to keep.
  defp unreplaceable(%{on_replace: :raise}, saved, rows) do
    held = MapSet.new(rows, &(&1 |> applied() |> Ecto.primary_key()))
    Enum.reject(saved, &MapSet.member?(held, Ecto.primary_key(&1)))
  end

  defp unreplaceable(_assoc, _saved, _rows), do: []

  defp keep_row(entry, saved_rows) do
    row = applied(entry)
    key = Ecto.primary_key(row)

    cond do
      new?(row) -> entry
      removed?(entry) and Map.has_key?(saved_rows, key) -> as_removed(saved_rows[key], entry)
      Map.has_key?(saved_rows, key) -> onto(entry, saved_rows[key])
      removed?(entry) or not changed?(entry) -> nil
      true -> as_new(entry)
    end
  end

  # A has_one: the row the editor holds, the saved one if it is that row.
  defp keep_one(assoc, saved, nil), do: remove_one(assoc, saved)

  defp keep_one(assoc, saved, held) do
    row = applied(held)

    cond do
      saved && Ecto.primary_key(row) == Ecto.primary_key(saved) -> onto(held, saved)
      saved && assoc.on_replace in [:raise, :update] -> held |> edited() |> onto_saved(saved) |> typed(held)
      new?(row) -> held
      changed?(held) -> as_new(held)
      true -> :keep
    end
  end

  # The saved row, taken out as the editor took it out.
  defp as_removed(saved, %Changeset{changes: changes}),
    do: saved |> Changeset.change(Map.take(changes, [:marked_as_deleted])) |> Map.put(:action, :delete)

  defp remove_one(_assoc, nil), do: :keep
  defp remove_one(%{on_replace: on_replace}, _saved) when on_replace in [:raise, :update], do: :keep
  defp remove_one(_assoc, _saved), do: nil

  # The editor's row onto the saved one: its changes, over the saved values.
  defp onto(%Changeset{} = held, saved) do
    if changed?(held), do: typed(%{held | data: saved, params: %{}}, held), else: saved
  end

  defp onto(_held, saved), do: saved

  # The editor's values onto a saved row it can't replace. The rows of the
  # row's own relations go onto the saved row's as the relation lets them
  # (`keep_one/3`, `keep_many/3`): saved rows it can't replace stay.
  defp onto_saved(edits, %row_schema{} = saved) do
    {nested, values} = Map.split(edits, fields(row_schema, []))

    Enum.reduce(nested, Changeset.change(saved, values), fn {name, held}, changeset ->
      assoc = row_schema.__schema__(:association, name)
      current = Map.get(saved, name)

      cond do
        # The saved row didn't load them: the editor's rows go as they are
        not Ecto.assoc_loaded?(current) ->
          %{changeset | changes: Map.put(changeset.changes, name, as_changes(held))}

        assoc.cardinality == :one ->
          put_kept(changeset, name, keep_one(assoc, current, held))

        true ->
          put_kept(changeset, name, keep_many(assoc, current, List.wrap(held)))
      end
    end)
  end

  defp as_changes(rows) when is_list(rows), do: Enum.map(rows, &as_changes/1)
  defp as_changes(%Changeset{} = row), do: row
  defp as_changes(nil), do: nil
  defp as_changes(row), do: row |> Changeset.change() |> Map.put(:action, :insert)

  defp changed?(%Changeset{changes: changes, errors: errors}), do: changes != %{} or errors != []
  defp changed?(_row), do: false

  defp edited(%Changeset{changes: changes} = held) do
    keys = held.data.__struct__.__schema__(:primary_key)
    Map.drop(changes, keys)
  end

  # A row in the form's data: its values, and the rows of its own relations
  # (an author's links), as new rows of the row it goes onto.
  defp edited(%row_schema{} = row) do
    row = new_struct(row)

    for name <- fields(row_schema, []),
        rows = Map.get(row, name),
        Ecto.assoc_loaded?(rows) and rows not in [nil, []],
        into: edits(row, struct(row_schema)),
        do: {name, rows}
  end

  # The form shows a row's params over its values: only what the editor
  # changed, or typed and didn't cast, stays a param.
  defp typed(%Changeset{} = changeset, %Changeset{params: params, changes: changes, errors: errors}) do
    names = Enum.map(Map.keys(changes) ++ Keyword.keys(errors), &Atom.to_string/1)
    params = Map.merge(changeset.params || %{}, Map.take(params || %{}, ["_key" | names]))
    errors = changeset.errors ++ Enum.reject(errors, fn {field, _} -> Keyword.has_key?(changeset.errors, field) end)
    %{changeset | params: params, errors: errors, valid?: changeset.valid? and errors == []}
  end

  defp typed(changeset, _row), do: changeset

  # A row the save removed that the editor changed: a new row, with a key of
  # its own, holding what the editor's form showed.
  defp as_new(entry) do
    entry
    |> applied()
    |> new_struct()
    |> Changeset.change()
    |> Map.put(:action, :insert)
    |> SubformHelpers.new_row()
  end

  defp new_struct(%row_schema{} = row) do
    row = Enum.reduce(row_schema.__schema__(:primary_key), row, &Map.put(&2, &1, nil))
    row = put_in(row.__meta__.state, :built)

    Enum.reduce(fields(row_schema, []), row, fn name, row ->
      case {row_schema.__schema__(:association, name), Map.get(row, name)} do
        {%Association.ManyToMany{}, _links} -> row
        {_assoc, rows} when is_list(rows) -> Map.put(row, name, Enum.map(rows, &new_struct/1))
        {_assoc, %_{__meta__: _} = one} -> Map.put(row, name, new_struct(one))
        _ -> row
      end
    end)
  end
end
