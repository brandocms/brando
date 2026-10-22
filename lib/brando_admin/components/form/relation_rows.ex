defmodule BrandoAdmin.Components.Form.RelationRows do
  @moduledoc false
  # The has_many, has_one and many_to_many relations of an entry form. They
  # don't ship between editors as field changes (`Form.sync_fields/1`), so
  # another editor's save (`Form.take_saved_entry/1`) is where they meet: a
  # form keeps the rows its editor changed (`carry/5`) and takes the saved
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
  save added is there too, unless it is one the editor added as well: a
  new row of the editor's and a row the save added are one row when they
  hold the same content, or name the same option in a multi-select
  (`keys`, `{schema, relation} => relation_key`). A relation whose rows
  can't be replaced (`on_replace: :raise`) keeps every saved row the
  editor didn't take out; a has_one the save filled takes the editor's new
  row as changes to it.

  A row carries what the editor typed into its fields that didn't cast,
  and the errors for it.
  """
  def carry(%Changeset{data: %schema{} = data} = saved, %Changeset{} = previous, base, field, keys \\ %{}) do
    assoc = schema.__schema__(:association, field)
    current = Map.get(data, field)
    base = if is_map(base), do: Map.get(base, field), else: current
    base = if Ecto.assoc_loaded?(base), do: base, else: current

    cond do
      not Ecto.assoc_loaded?(current) -> carry_unloaded(saved, previous, field)
      assoc.cardinality == :one -> put_carried(saved, field, carry_one(assoc, current, base, held(previous, field), keys))
      true -> put_carried(saved, field, carry_many(assoc, current, base, held(previous, field), keys))
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

  # The rows a row (or the entry's changeset) holds: changesets from its
  # changes, or the structs in its data. In a list, a row the editor took
  # out (`:delete`, a multi-select's unpick) stays, as the editor's intent;
  # one put_assoc replaced does not.
  defp held(%Changeset{} = changeset, field) do
    case Map.fetch(changeset.changes, field) do
      {:ok, rows} when is_list(rows) -> Enum.reject(rows, &match?(%Changeset{action: :replace}, &1))
      {:ok, row} -> if removed?(row), do: nil, else: row
      :error -> Map.get(changeset.data, field)
    end
  end

  defp held(row, field), do: Map.get(row, field)

  defp removed?(%Changeset{action: action}), do: action in [:replace, :delete]
  defp removed?(_row), do: false

  defp applied(%Changeset{} = row), do: Changeset.apply_changes(row)
  defp applied(row), do: row

  defp new?(row), do: Enum.all?(Ecto.primary_key(row), fn {_key, value} -> is_nil(value) end)

  defp by_key(rows), do: Map.new(rows, &{Ecto.primary_key(&1), &1})

  # An entry linked stays linked, and one unlinked stays unlinked, unless
  # the links can't be replaced.
  defp carry_many(%Association.ManyToMany{} = assoc, saved, base, held, _keys) do
    shown = for entry <- List.wrap(held), not removed?(entry), do: applied(entry)
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

  defp carry_many(assoc, saved, base, held, keys) do
    saved_rows = by_key(saved)
    base_rows = by_key(base)
    held = Enum.with_index(List.wrap(held))
    matches = same_new_rows(assoc, held, Enum.reject(saved, &Map.has_key?(base_rows, Ecto.primary_key(&1))), keys)

    # Each held row as it goes onto the saved ones: `{:row, key, value}` for
    # a saved row, `{:new, anchor, value}` for a row to insert after the
    # saved row `anchor` (the held row before it), or `:drop`.
    {placed, _anchor} =
      Enum.map_reduce(held, :start, fn {entry, at}, anchor ->
        place(entry, anchor, Map.get(matches, at), {saved_rows, base_rows}, keys)
      end)

    shown_keys =
      MapSet.new(
        for({entry, _at} <- held, do: entry |> applied() |> Ecto.primary_key()) ++
          Enum.map(Map.values(matches), &Ecto.primary_key(elem(&1, 1)))
      )

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

  # The editor's new rows that are rows the save added (`fresh`): by their
  # multi-select option where the relation has one, by their content
  # otherwise. Each saved row is one held row's at most. Returns the saved
  # row for each held row's position.
  defp same_new_rows(assoc, held, fresh, keys) do
    same = sameness(assoc, keys)

    {matches, _fresh} =
      Enum.reduce(held, {%{}, fresh}, fn {entry, at}, {matches, fresh} ->
        row = applied(entry)

        with false <- removed?(entry),
             true <- new?(row),
             index when is_integer(index) <- Enum.find_index(fresh, &(same.(&1) == same.(row))) do
          {Map.put(matches, at, {assoc, Enum.at(fresh, index)}), List.delete_at(fresh, index)}
        else
          _ -> {matches, fresh}
        end
      end)

    matches
  end

  # A pick holds the option as the browser sent it, a string.
  defp sameness(assoc, keys) do
    case option_key(assoc, keys) do
      nil -> &Map.delete(row_content(assoc, &1), :sequence)
      key -> &to_string(Map.get(&1, key))
    end
  end

  defp option_key(%{owner: owner, field: field}, keys), do: Map.get(keys, {owner, field})

  # A new row of the editor's that is a row the save added: what it holds
  # but the option it names is its change to the saved row.
  defp place(entry, _anchor, {assoc, %_{} = same}, _rows, keys) do
    key = Ecto.primary_key(same)

    base =
      case option_key(assoc, keys) do
        nil -> blank(same)
        option -> Map.put(blank(same), option, Map.get(applied(entry), option))
      end

    {{:row, key, carry_row(same, base, entry, keys)}, key}
  end

  defp place(entry, anchor, nil, {saved_rows, base_rows}, keys) do
    row = applied(entry)
    key = Ecto.primary_key(row)

    cond do
      removed?(entry) and Map.has_key?(saved_rows, key) ->
        {{:row, key, as_removed(saved_rows[key], entry)}, key}

      removed?(entry) ->
        {:drop, anchor}

      new?(row) ->
        {{:new, anchor, as_insert(entry)}, anchor}

      Map.has_key?(saved_rows, key) ->
        {{:row, key, carry_row(saved_rows[key], Map.get(base_rows, key), entry, keys)}, key}

      edits(row, Map.get(base_rows, key)) == %{} or marked_as_deleted?(row) ->
        {:drop, anchor}

      true ->
        {{:new, anchor, rescued(entry, Map.get(base_rows, key))}, anchor}
    end
  end

  # The saved row, taken out as the editor took it out.
  defp as_removed(saved, %Changeset{changes: changes}),
    do: saved |> Changeset.change(Map.take(changes, [:marked_as_deleted])) |> Map.put(:action, :delete)

  # A row the save removed that the editor changed, as a new row. It has
  # a key of its own, and is the row the browser names by its old id, from
  # the form it showed before (`take_row/6`).
  defp rescued(entry, base) do
    row = applied(entry)

    rescued =
      row
      |> as_new()
      |> as_insert()
      |> keep_typed(entry, Map.keys(edits(row, base)))
      |> SubformHelpers.new_row()

    case Map.get(row, :id) do
      nil -> rescued
      id -> %{rescued | params: Map.put(rescued.params, "id", to_string(id))}
    end
  end

  # A new row of `schema`, its relations loaded and empty: what a row the
  # editor added has changed.
  defp blank(%row_schema{}) do
    Enum.reduce(fields(row_schema, []), struct(row_schema), fn name, row ->
      Map.put(row, name, if(row_schema.__schema__(:association, name).cardinality == :one, do: nil, else: []))
    end)
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
  defp carry_one(assoc, saved, base, held, keys) do
    case one_onto(assoc, saved, base, held, keys) do
      ^saved -> :keep
      value -> value
    end
  end

  defp one_onto(assoc, saved, base, nil, _keys), do: remove_one(assoc, saved, base)

  defp one_onto(_assoc, nil, base, held, _keys) do
    row = applied(held)

    cond do
      new?(row) -> as_insert(held)
      edits(row, base) == %{} -> :keep
      true -> held |> applied() |> as_new() |> as_insert() |> keep_typed(held, Map.keys(edits(row, base)))
    end
  end

  defp one_onto(_assoc, saved, base, held, keys) do
    row = applied(held)

    if new?(row),
      do: carry_row(saved, blank(row), held, keys),
      else: carry_row(saved, reference(row, base, saved), held, keys)
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

  # The saved row with the editor's changes to it: what `entry` holds
  # otherwise than `base`, the row its form was built on, and what it typed
  # that didn't cast.
  defp carry_row(saved, base, entry, keys) do
    edits = edits(applied(entry), base)
    typed = Map.keys(edits) ++ Keyword.keys(typing_errors(entry))

    if typed == [],
      do: saved,
      else: saved |> put_edits(base, edits, entry, keys) |> keep_typed(entry, typed)
  end

  # Values typed that didn't cast; other errors are the row's validations,
  # which the next change runs again on the saved row.
  defp typing_errors(%Changeset{errors: errors}),
    do: Enum.filter(errors, fn {_field, {_message, opts}} -> opts[:validation] == :cast end)

  defp typing_errors(_row), do: []

  # What the editor typed into `fields` of the row, as the browser sent it,
  # and the errors for it: the form shows a row's params over its values.
  defp keep_typed(%Changeset{} = changeset, %Changeset{params: params, errors: errors}, fields) do
    names = Enum.map(fields, &Atom.to_string/1)
    errors = Keyword.drop(changeset.errors, fields) ++ Keyword.take(errors, fields)
    params = Map.merge(changeset.params || %{}, Map.take(params || %{}, names))

    %{changeset | params: params, errors: errors, valid?: errors == [] and rows_valid?(changeset)}
  end

  defp keep_typed(changeset, _row, _fields), do: changeset

  # Whether the rows in a changeset's relations are valid, as `put_assoc`
  # counts them.
  defp rows_valid?(%Changeset{changes: changes}) do
    changes
    |> Map.values()
    |> List.flatten()
    |> Enum.all?(&(not match?(%Changeset{valid?: false}, &1)))
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

  defp put_edits(%row_schema{} = saved, base, edits, entry, keys) do
    {relations, values} = Map.split(edits, fields(row_schema, []))
    changeset = saved |> Changeset.change(values) |> Map.put(:action, :update)

    Enum.reduce(Map.keys(relations), changeset, fn name, changeset ->
      held = held(entry, name)
      assoc = row_schema.__schema__(:association, name)
      current = Map.get(saved, name)
      current = if Ecto.assoc_loaded?(current), do: current, else: Map.get(base, name)

      value =
        if assoc.cardinality == :one,
          do: carry_one(assoc, current, Map.get(base, name), held, keys),
          else: carry_many(assoc, current, Map.get(base, name), held, keys)

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
  but for what the event changed in that row, as `changeset` cast it: the
  field it names (`row_field`, as in `_target`) and the fields the row
  holds otherwise than the browser showed it, which is one of `stale`
  (`RelationRows.rows/2` of the relations it replaced). The row's other
  fields stay as `previous` has them. Returns the changeset, and whether
  the other rows sent were the old ones.
  """
  def take_row(%Changeset{} = changeset, %Changeset{} = previous, field, key, row_field, stale) do
    sent = SubformHelpers.current_entries(changeset, field)
    held = SubformHelpers.current_entries(previous, field)

    case Enum.find(sent, &(row_key(&1) == key)) do
      nil ->
        {changeset, false}

      row ->
        assoc = changeset.data.__struct__.__schema__(:association, field)
        echoed? = content(assoc, others(sent, key)) != content(assoc, others(held, key))
        taken = taken_fields(assoc, sent, row, row_field, stale)
        {SubformHelpers.put_entries(changeset, field, put_row(held, key, row, taken)), echoed?}
    end
  end

  defp others(rows, key), do: for(row <- rows, not named?(row, key), do: applied(row))

  defp put_row(rows, key, row, taken) do
    if Enum.any?(rows, &named?(&1, key)),
      do: Enum.map(rows, &if(named?(&1, key), do: take_fields(&1, row, taken), else: &1)),
      else: rows ++ [row]
  end

  # The fields of `row` the event changed: the one it names, and the ones
  # that differ from the row in the form the browser showed (the stale rows
  # that are the sent ones but for this row). All of them if neither is known.
  defp taken_fields(%{related: row_schema} = assoc, sent, row, row_field, stale) do
    shown = for entry <- sent, do: row_content(assoc, applied(entry))
    at = Enum.find_index(sent, &(&1 == row))
    named = Enum.filter(fields(row_schema, []) ++ row_schema.__schema__(:fields), &(Atom.to_string(&1) == row_field))

    changed =
      case Enum.find(List.wrap(stale), &shown_before?(&1, shown, at)) do
        nil -> []
        before -> for {name, value} <- Enum.at(shown, at), Map.get(Enum.at(before, at), name) != value, do: name
      end

    case Enum.uniq(named ++ changed) do
      [] -> :all
      taken -> taken
    end
  end

  defp shown_before?(before, shown, at) when is_list(before) and is_integer(at) do
    length(before) == length(shown) and is_map(Enum.at(shown, at)) and
      List.delete_at(before, at) == List.delete_at(shown, at)
  end

  defp shown_before?(_before, _shown, _at), do: false

  defp take_fields(_held, row, :all), do: row

  defp take_fields(%Changeset{data: %row_schema{}} = held, row, taken) do
    relations = fields(row_schema, [])

    Enum.reduce(taken, held, &take_field(&2, row, &1, &1 in relations))
  end

  defp take_field(held, row, name, true = _relation?) do
    case Map.fetch(row.changes, name) do
      {:ok, value} -> %{held | changes: Map.put(held.changes, name, value)}
      :error -> %{held | changes: Map.delete(held.changes, name)}
    end
  end

  defp take_field(held, row, name, false = _relation?) do
    held
    |> Changeset.put_change(name, Changeset.get_field(row, name))
    |> keep_typed(row, [name])
  end

  # Whether the browser names `row` by `key`: by its id, its `_key`, or the
  # id of the saved row it was before the save removed it (`rescued/2`).
  defp named?(row, key), do: row_key(row) == key or old_key(row) == key

  defp old_key(%Changeset{params: %{"id" => id}}) when is_binary(id) and id != "", do: "id-" <> id
  defp old_key(_row), do: nil

  # A row cast from a saved row the save removed has no id of its own: the
  # params still name it.
  defp row_key(%Changeset{} = row) do
    case {SubformHelpers.row_key(row), row.params} do
      {nil, %{"id" => id}} when is_binary(id) and id != "" -> "id-" <> id
      {key, _params} -> key
    end
  end
end
