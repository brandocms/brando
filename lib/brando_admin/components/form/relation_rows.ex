defmodule BrandoAdmin.Components.Form.RelationRows do
  @moduledoc false
  # The has_many, has_one and many_to_many relations of an entry form. They
  # don't ship between editors as field changes (`Form.sync_fields/1`), so
  # another editor's save (`Form.take_saved_entry/1`) is where they meet: a
  # form keeps the rows its editor changed (`carry/4`) and takes the saved
  # rows in the rest. Rows compare by content (`rows/2`): the rows a form
  # builds again from the browser's params are new structs.

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
  def rows(%Changeset{data: %schema{}} = changeset, field) do
    case shown(changeset, field) do
      %Association.NotLoaded{} -> :not_loaded
      rows -> content(schema.__schema__(:association, field), rows)
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

  defp content(assoc, rows), do: for(row <- List.wrap(rows), not marked_as_deleted?(row), do: row_content(assoc, row))

  defp row_content(%Association.ManyToMany{}, row), do: Ecto.primary_key(row)

  defp row_content(%{related_key: owner_key}, %row_schema{} = row) do
    skip = [owner_key, :inserted_at, :updated_at | row_schema.__schema__(:primary_key)]
    values = Map.take(row, row_schema.__schema__(:fields) -- skip)

    for name <- fields(row_schema, []),
        Ecto.assoc_loaded?(Map.get(row, name)),
        into: values,
        do: {name, content(row_schema.__schema__(:association, name), Map.get(row, name))}
  end

  defp marked_as_deleted?(row), do: Map.get(row, :marked_as_deleted) == true

  @doc """
  The relation of `saved`, with the rows the editor changed carried over
  from `previous`, the form it had: `base` is the entry that form was built
  on, so a row's changes are the editor's own, as the form holds them (in
  its changes, or applied into its data by an asset delivery,
  `Form.commit_entry_field_asset/5`).

  A row the editor changed keeps its changes, applied onto the saved row,
  or as a new row if the save removed it; a row it added stays, and one it
  removed stays removed. Every other row is the saved one, and a row the
  save added is there too. A relation whose rows can't be replaced
  (`on_replace: :raise`) keeps every saved row; a has_one the save filled
  takes the editor's new row as changes to it.
  """
  def carry(%Changeset{data: %schema{} = data} = saved, %Changeset{} = previous, base, field) do
    assoc = schema.__schema__(:association, field)
    current = Map.get(data, field)
    base = if is_map(base), do: Map.get(base, field), else: current
    base = if Ecto.assoc_loaded?(base), do: base, else: current

    cond do
      not Ecto.assoc_loaded?(current) -> carry_unloaded(saved, previous, field)
      assoc.cardinality == :one -> put_carried(saved, field, carry_one(assoc, current, base, held(previous, field)))
      true -> put_carried(saved, field, carry_many(assoc, current, base, held(previous, field)))
    end
  end

  # The saved entry didn't load the relation: the form's change goes as is.
  defp carry_unloaded(saved, previous, field) do
    case Map.fetch(previous.changes, field) do
      {:ok, edit} -> %{saved | changes: Map.put(saved.changes, field, edit)}
      :error -> saved
    end
  end

  defp put_carried(changeset, _field, :keep), do: changeset
  defp put_carried(changeset, field, value), do: Changeset.put_assoc(changeset, field, value)

  # The rows `changeset` holds: changesets from its changes (not the ones
  # removed), or the structs in its data.
  defp held(changeset, field) do
    case Map.fetch(changeset.changes, field) do
      {:ok, rows} when is_list(rows) -> Enum.reject(rows, &removed?/1)
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

  # An entry linked stays linked, and one unlinked stays unlinked, unless
  # the links can't be replaced.
  defp carry_many(%Association.ManyToMany{} = assoc, saved, base, held) do
    shown = held |> List.wrap() |> Enum.map(&applied/1)
    shown_keys = MapSet.new(shown, &Ecto.primary_key/1)
    base_keys = MapSet.new(base, &Ecto.primary_key/1)
    saved_keys = MapSet.new(saved, &Ecto.primary_key/1)

    unlinked =
      if assoc.on_replace == :raise,
        do: MapSet.new(),
        else: MapSet.difference(base_keys, shown_keys)

    linked =
      Enum.reject(
        shown,
        &(MapSet.member?(base_keys, Ecto.primary_key(&1)) or MapSet.member?(saved_keys, Ecto.primary_key(&1)))
      )

    Enum.reject(saved, &MapSet.member?(unlinked, Ecto.primary_key(&1))) ++ linked
  end

  defp carry_many(assoc, saved, base, held) do
    saved_rows = by_key(saved)
    base_rows = by_key(base)

    # Each held row as it goes onto the saved ones: `{:row, key, value}` for
    # a saved row, `{:new, anchor, value}` for a row to insert after the
    # saved row `anchor` (the held row before it), or `:drop`.
    {placed, _anchor} =
      held
      |> List.wrap()
      |> Enum.map_reduce(:start, &place(&1, &2, saved_rows, base_rows))

    shown_keys = MapSet.new(for(entry <- List.wrap(held), do: entry |> applied() |> Ecto.primary_key()))
    # The saved rows the form doesn't hold: the save added them, or the
    # editor removed them, which a relation that can't replace a row keeps.
    untouched =
      Enum.reject(saved, fn row ->
        key = Ecto.primary_key(row)
        MapSet.member?(shown_keys, key) or (Map.has_key?(base_rows, key) and assoc.on_replace != :raise)
      end)

    if Enum.any?(placed, &match?({:row, _, %Changeset{changes: %{sequence: _}}}, &1)),
      do: in_held_order(placed) ++ untouched,
      else: in_saved_order(placed, saved, untouched)
  end

  defp place(entry, anchor, saved_rows, base_rows) do
    row = applied(entry)
    key = Ecto.primary_key(row)

    cond do
      new?(row) ->
        {{:new, anchor, as_insert(entry)}, anchor}

      Map.has_key?(saved_rows, key) ->
        {{:row, key, carry_row(saved_rows[key], Map.get(base_rows, key), row)}, key}

      edits(row, Map.get(base_rows, key)) == %{} or marked_as_deleted?(row) ->
        {:drop, anchor}

      true ->
        {{:new, anchor, as_insert(as_new(row))}, anchor}
    end
  end

  # The editor reordered the rows.
  defp in_held_order(placed) do
    for item <- placed, item != :drop, do: elem(item, 2)
  end

  # The saved order, with the editor's new rows after the row they follow.
  defp in_saved_order(placed, saved, untouched) do
    rows = for {:row, key, value} <- placed, into: %{}, do: {key, value}
    added = Enum.group_by(for({:new, anchor, value} <- placed, do: {anchor, value}), &elem(&1, 0), &elem(&1, 1))
    untouched = MapSet.new(untouched, &Ecto.primary_key/1)

    ordered =
      Enum.flat_map(saved, fn row ->
        key = Ecto.primary_key(row)

        value =
          cond do
            Map.has_key?(rows, key) -> [rows[key]]
            MapSet.member?(untouched, key) -> [row]
            true -> []
          end

        value ++ Map.get(added, key, [])
      end)

    saved_keys = MapSet.new(saved, &Ecto.primary_key/1)
    orphans = for {anchor, values} <- added, anchor != :start, not MapSet.member?(saved_keys, anchor), do: values
    Map.get(added, :start, []) ++ ordered ++ List.flatten(orphans)
  end

  # A has_one: the row the editor holds, onto the saved one.
  defp carry_one(assoc, saved, base, held) do
    case one_onto(assoc, saved, base, held, held && applied(held)) do
      ^saved -> :keep
      value -> value
    end
  end

  defp one_onto(assoc, saved, base, _held, nil), do: remove_one(assoc, saved, base)

  defp one_onto(_assoc, nil, base, held, row) do
    cond do
      new?(row) -> as_insert(held)
      edits(row, base) == %{} -> :keep
      true -> as_insert(as_new(row))
    end
  end

  defp one_onto(_assoc, saved, base, _held, row) do
    if new?(row),
      do: carry_row(saved, struct(row.__struct__), row),
      else: carry_row(saved, reference(row, base, saved), row)
  end

  # The editor removed the row it had: the saved one goes, if it is that row
  # and the relation lets it.
  defp remove_one(_assoc, nil, _base), do: :keep
  defp remove_one(_assoc, _saved, nil), do: :keep
  defp remove_one(%{on_replace: on_replace}, _saved, _base) when on_replace in [:raise, :update], do: :keep

  defp remove_one(_assoc, saved, base) do
    if Ecto.primary_key(saved) == Ecto.primary_key(base), do: nil, else: :keep
  end

  defp reference(row, base, saved) do
    key = Ecto.primary_key(row)

    cond do
      base && Ecto.primary_key(base) == key -> base
      Ecto.primary_key(saved) == key -> saved
      true -> nil
    end
  end

  # The saved row with the editor's changes to it: what `row` holds otherwise
  # than `base`, the row its form was built on.
  defp carry_row(saved, base, row) do
    case edits(row, base) do
      edits when edits == %{} -> saved
      edits -> put_edits(saved, base, edits)
    end
  end

  defp edits(_row, nil), do: %{}

  defp edits(%row_schema{} = row, base) do
    values =
      for field <- edited_fields(row_schema),
          Map.get(row, field) != Map.get(base, field),
          into: %{},
          do: {field, Map.get(row, field)}

    for name <- fields(row_schema, []),
        Ecto.assoc_loaded?(Map.get(row, name)),
        Ecto.assoc_loaded?(Map.get(base, name)),
        nested_content(row_schema, name, row) != nested_content(row_schema, name, base),
        into: values,
        do: {name, Map.get(row, name)}
  end

  defp nested_content(row_schema, name, row), do: content(row_schema.__schema__(:association, name), Map.get(row, name))

  defp edited_fields(row_schema) do
    marked = if :marked_as_deleted in row_schema.__schema__(:virtual_fields), do: [:marked_as_deleted], else: []
    row_schema.__schema__(:fields) -- ([:inserted_at, :updated_at | row_schema.__schema__(:primary_key)] ++ marked)
  end

  defp put_edits(%row_schema{} = saved, base, edits) do
    {relations, values} = Map.split(edits, fields(row_schema, []))
    changeset = saved |> Changeset.change(values) |> Map.put(:action, :update)

    Enum.reduce(relations, changeset, fn {name, held}, changeset ->
      assoc = row_schema.__schema__(:association, name)
      current = Map.get(saved, name)
      current = if Ecto.assoc_loaded?(current), do: current, else: Map.get(base, name)

      value =
        if assoc.cardinality == :one,
          do: carry_one(assoc, current, Map.get(base, name), held),
          else: carry_many(assoc, current, Map.get(base, name), held)

      case value do
        :keep -> changeset
        value -> Changeset.put_assoc(%{changeset | data: Map.put(changeset.data, name, current)}, name, value)
      end
    end)
  end

  # A row to insert: as the form holds it, or the row the save removed as a
  # new one.
  defp as_insert(%Changeset{} = row), do: row
  defp as_insert(row), do: row |> Changeset.change() |> Map.put(:action, :insert)

  defp as_new(%row_schema{} = row) do
    row = Enum.reduce(row_schema.__schema__(:primary_key), row, &Map.put(&2, &1, nil))
    row = put_in(row.__meta__.state, :built)

    Enum.reduce(fields(row_schema, []), row, fn name, row ->
      case {row_schema.__schema__(:association, name), Map.get(row, name)} do
        {%Association.ManyToMany{}, _links} -> row
        {_assoc, rows} when is_list(rows) -> Map.put(row, name, Enum.map(rows, &as_new/1))
        {_assoc, %_{__meta__: _} = one} -> Map.put(row, name, as_new(one))
        _ -> row
      end
    end)
  end

  @doc """
  The browser's change in one row (`key`, `SubformHelpers.row_key/1`) of a
  relation another editor's change replaced, sent from the form it showed
  before (`Form.drop_echoes/5`): the relation stays as `previous` has it,
  but for that row as `changeset` cast it. Returns the changeset, and
  whether the other rows sent were the old ones.
  """
  def take_row(%Changeset{} = changeset, %Changeset{} = previous, field, key) do
    sent = SubformHelpers.current_entries(changeset, field)
    held = SubformHelpers.current_entries(previous, field)

    case Enum.find(sent, &(row_key(&1) == key)) do
      nil ->
        {changeset, false}

      row ->
        assoc = changeset.data.__struct__.__schema__(:association, field)
        echoed? = content(assoc, others(sent, key)) != content(assoc, others(held, key))
        {SubformHelpers.put_entries(changeset, field, put_row(held, key, row)), echoed?}
    end
  end

  defp others(rows, key), do: for(row <- rows, row_key(row) != key, do: applied(row))

  defp put_row(rows, key, row) do
    if Enum.any?(rows, &(row_key(&1) == key)),
      do: Enum.map(rows, &if(row_key(&1) == key, do: row, else: &1)),
      else: rows ++ [row]
  end

  # A row cast from a saved row the save removed has no id of its own: the
  # params still name it.
  defp row_key(%Changeset{} = row) do
    case {SubformHelpers.row_key(row), row.params} do
      {nil, %{"id" => id}} when is_binary(id) and id != "" -> "id-" <> id
      {key, _params} -> key
    end
  end
end
