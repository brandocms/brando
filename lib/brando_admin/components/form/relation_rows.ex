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
  #
  # An embedded list (`embeds_many`) ships between editors as a field, but
  # another editor's save that reaches a form whose editor changed its rows
  # is kept here too, row by row (`keep_list/5`), when its rows carry keys
  # (`embedded_rows?/4`): this editor's own edits (`Form.RowEdits`) on top
  # of the saved rows. It has no conflict to settle: the rows the save added
  # come in. An `embeds_one` is kept as a has_one is (`keep/5`), with only
  # the fields this editor changed over the saved row.

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

  An embedded one that is the saved row keeps only the fields `edits`
  records (`Form.RowEdits`): one the editor only received is the save's.
  """
  def keep(%Changeset{data: %schema{} = data} = saved, %Changeset{} = previous, base, field, edits \\ nil) do
    assoc = schema.__schema__(:association, field) || schema.__schema__(:embed, field)
    current = Map.get(data, field)
    base = if is_map(base), do: Map.get(base, field)
    base = if Ecto.assoc_loaded?(base), do: base, else: nil
    edits = if match?(%Ecto.Embedded{}, assoc), do: edits

    cond do
      not Ecto.assoc_loaded?(current) ->
        keep_unloaded(saved, previous, field)

      assoc.cardinality == :one ->
        put_kept(saved, field, keep_one(assoc, current, as_change(held(previous, field), base), base, edits))

      true ->
        put_kept(
          saved,
          field,
          keep_many(assoc, current, Enum.map(List.wrap(held(previous, field)), &as_change(&1, base)))
        )
    end
  end

  @doc """
  An embedded list as `previous`, the form, holds it, on `saved`: the saved
  rows, with this editor's own `edits` (`Form.RowEdits`) on top. A row they
  typed in keeps the fields they typed, over the saved values; the rows they
  added stay, those they removed stay out, and if they moved a row, their
  order wins. Everything else in the form is the save's: a value it holds
  because another editor sent it is never an edit.

  A new row (no id yet) is the saved row its key names in `keys`, the
  saver's map of the new rows it wrote (`_key` => `id-…`). One the map
  doesn't name stays if this editor added or typed in it; otherwise it is a
  row the save doesn't hold, and goes. Without a map (a save no form made,
  `nil`) every new row stays. A saved row the save removed comes back as a
  new row if the editor typed in it, and goes otherwise.

  Returns the changeset and the rows that go by another key now
  (old key => new key).
  """
  def keep_list(%Changeset{data: data} = saved, %Changeset{} = previous, field, edits, keys) do
    saved_rows = Map.get(data, field)
    by_key = Map.new(saved_rows, &{SubformHelpers.row_key(&1), &1})
    removed = MapSet.new(edits.removed, &(saved_key(&1, by_key, keys) || &1))

    {rows, renamed} =
      previous
      |> held(field)
      |> List.wrap()
      |> Enum.reduce({[], removed_renamed(edits.removed, keys)}, fn entry, {rows, renamed} ->
        key = SubformHelpers.row_key(entry)
        typed = Map.get(edits.typed, key, MapSet.new())

        case kept_row(entry, key, saved_key(key, by_key, keys), by_key, typed, edits, keys) do
          nil -> {rows, renamed}
          {id, row} -> {[{id, row} | rows], rename(renamed, key, id, row)}
        end
      end)

    rows = Enum.reverse(rows)
    held_ids = MapSet.new(rows, &elem(&1, 0))

    added =
      for row <- saved_rows,
          key = SubformHelpers.row_key(row),
          not MapSet.member?(held_ids, key) and not MapSet.member?(removed, key),
          do: {key, row}

    by_id = Map.new(rows ++ added)
    editor = Enum.map(rows, &elem(&1, 0))
    save = for row <- saved_rows, key = SubformHelpers.row_key(row), Map.has_key?(by_id, key), do: key
    {lead, other} = if edits.moved?, do: {editor, save}, else: {save, editor}
    kept = lead |> interleave(other) |> Enum.map(&Map.fetch!(by_id, &1))

    {Changeset.put_embed(saved, field, kept), renamed}
  end

  # The saved row's key a row of the form goes by: its own, or the one the
  # saver's map gives its `_key`.
  defp saved_key(key, by_key, keys) do
    key = if Map.has_key?(by_key, key), do: key, else: Map.get(keys || %{}, key)
    if Map.has_key?(by_key, key), do: key
  end

  # A row of the form, by its place in the save: the saved row it is, with
  # the fields the editor typed on top; a new row of this editor's; a saved
  # row the save removed, as a new one if they typed in it. `nil` when it
  # goes.
  defp kept_row(entry, key, saved_key, by_key, typed, edits, keys) do
    cond do
      saved_key ->
        {saved_key, with_typed(entry, Map.fetch!(by_key, saved_key), typed)}

      new?(applied(entry)) ->
        if is_nil(keys) or is_nil(key) or MapSet.member?(edits.added, key) or MapSet.size(typed) > 0,
          do: {make_ref(), entry}

      MapSet.size(typed) > 0 ->
        {make_ref(), as_new(entry)}

      true ->
        nil
    end
  end

  # The new rows the editor removed that the save wrote: their removal goes
  # by the saved key from then on, so a later save that still holds the
  # row doesn't bring it back.
  defp removed_renamed(removed, keys) do
    for key <- removed, id = Map.get(keys || %{}, key), into: %{}, do: {key, id}
  end

  defp rename(renamed, key, id, row) do
    case if(is_reference(id), do: SubformHelpers.row_key(row), else: id) do
      ^key -> renamed
      nil -> renamed
      new_key -> Map.put(renamed, key, new_key)
    end
  end

  # The saved row, with the fields the editor typed as the form holds them:
  # their values, and what they typed that didn't cast with its error.
  defp with_typed(entry, saved, typed) do
    if MapSet.size(typed) == 0 do
      saved
    else
      fields = MapSet.to_list(typed)
      changeset = Changeset.change(saved, Map.take(applied(entry), fields))
      {params, errors} = typed_input(entry, fields)
      %{changeset | action: :update, params: params, errors: errors, valid?: changeset.valid? and errors == []}
    end
  end

  defp typed_input(%Changeset{params: params, errors: errors}, fields),
    do: {Map.take(params || %{}, Enum.map(fields, &Atom.to_string/1)), Keyword.take(errors, fields)}

  defp typed_input(_row, _fields), do: {%{}, []}

  @doc """
  The new rows of each embedded list a save wrote, by their key in the
  form that saved (`_key` => `id-…`), for the other forms to tell them by
  (`keep_list/5`): the new rows of `changeset`, the save's, in order, are
  the new rows of `entry`, the saved entry.
  """
  def written(%Changeset{data: %schema{}, changes: changes}, entry) do
    for field <- schema.__schema__(:embeds),
        rows when is_list(rows) <- [Map.get(changes, field)],
        sent = Enum.reject(rows, &removed?/1),
        saved = Map.get(entry, field),
        is_list(saved) and length(sent) == length(saved),
        keys = written_keys(sent, saved),
        keys != %{},
        into: %{},
        do: {field, keys}
  end

  defp written_keys(sent, saved) do
    for {%Changeset{action: :insert} = row, saved_row} <- Enum.zip(sent, saved),
        key = SubformHelpers.row_key(row),
        is_binary(key),
        into: %{},
        do: {key, SubformHelpers.row_key(saved_row)}
  end

  @doc """
  Embedded rows as they are stored: a map field read back has string keys,
  whatever the form held.
  """
  def stored(rows),
    do: rows |> List.wrap() |> Enum.map(&Ecto.embedded_dump(&1, :json)) |> Jason.encode!() |> Jason.decode!()

  @doc """
  Whether `keep/4` (an `embeds_one`) or `keep_list/5` can keep the embedded rows of `field` row by row: the
  rows carry a primary key, in the saved entry and in `base`, the entry
  the form was built on. A schema without one (`primary_key: false`), or a
  row stored without its key, can't be matched, and the form keeps the
  editor's list whole. So does an embedded one whose removal in
  `previous`, the form, didn't cast (a required one): the form keeps
  showing it removed, with its error.
  """
  def embedded_rows?(%Changeset{data: %schema{} = data}, %Changeset{} = previous, base, field) do
    case schema.__schema__(:embed, field) do
      %Ecto.Embedded{related: related, cardinality: cardinality} ->
        related.__schema__(:primary_key) != [] and
          not (cardinality == :one and Keyword.has_key?(previous.errors, field)) and
          Enum.all?(List.wrap(Map.get(data, field)) ++ List.wrap(base && Map.get(base, field)), &(not new?(&1)))

      nil ->
        false
    end
  end

  # A row of the form's data the form changed itself: its changes against
  # the row in `base`.
  defp as_change(%Changeset{} = row, _base), do: row

  defp as_change(%_{} = row, base) do
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

  defp put_kept(%Changeset{data: %schema{}} = changeset, field, value) do
    if schema.__schema__(:embed, field),
      do: Changeset.put_embed(changeset, field, value),
      else: Changeset.put_assoc(changeset, field, value)
  end

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

  # `lead` with the rows only `other` has: after the nearest row before it
  # in `other` that is in the list, else before the nearest one after it,
  # else last.
  defp interleave(order, order), do: order

  defp interleave(lead, other) do
    anchors = MapSet.new(lead)

    if unique_keys?(lead, anchors) and unique_keys?(other, MapSet.new(other)) do
      {prefix, anchored} = Enum.split_while(other, &(not MapSet.member?(anchors, &1)))
      insert_runs(lead, prefix, anchored, anchors)
    else
      interleave_repeated_keys(lead, other)
    end
  end

  defp unique_keys?(order, keys), do: MapSet.size(keys) == length(order) and not MapSet.member?(keys, nil)

  defp insert_runs(lead, prefix, [], _anchors), do: lead ++ prefix

  defp insert_runs(lead, prefix, [first | rest], anchors) do
    {_, following} =
      Enum.reduce(rest, {first, %{}}, fn key, {anchor, following} ->
        if MapSet.member?(anchors, key) do
          {key, following}
        else
          {anchor, Map.update(following, anchor, [key], &[key | &1])}
        end
      end)

    Enum.flat_map(lead, fn key ->
      before = if key == first, do: prefix, else: []
      before ++ [key | Enum.reverse(Map.get(following, key, []))]
    end)
  end

  defp interleave_repeated_keys(lead, other) do
    other
    |> Enum.with_index()
    |> Enum.reduce(lead, fn {key, index}, list ->
      if key in list, do: list, else: place(list, key, Enum.take(other, index), Enum.drop(other, index + 1))
    end)
  end

  defp place(list, key, before_rows, after_rows) do
    before = before_rows |> Enum.reverse() |> Enum.find(&(&1 in list))
    next = Enum.find(after_rows, &(&1 in list))

    cond do
      before -> List.insert_at(list, Enum.find_index(list, &(&1 == before)) + 1, key)
      next -> List.insert_at(list, Enum.find_index(list, &(&1 == next)), key)
      true -> list ++ [key]
    end
  end

  # A has_one: the row the editor holds, the saved one if it is that row.
  # `base` is the row the form was built on. An embedded one with `edits`
  # (`Form.RowEdits`) keeps only the fields they record over the saved row.
  defp keep_one(assoc, saved, held, base \\ nil, edits \\ nil)
  defp keep_one(assoc, saved, nil, base, _edits), do: remove_one(assoc, saved, base)

  defp keep_one(assoc, saved, held, _base, edits) do
    row = applied(held)

    cond do
      saved && Ecto.primary_key(row) == Ecto.primary_key(saved) -> onto(held, saved, edits)
      saved && assoc.on_replace in [:raise, :update] -> held |> edited() |> onto_saved(saved) |> typed(held)
      new?(row) -> held
      changed?(held) -> as_new(held)
      true -> :keep
    end
  end

  # The saved row, taken out as the editor took it out.
  defp as_removed(saved, %Changeset{changes: changes}),
    do: saved |> Changeset.change(Map.take(changes, [:marked_as_deleted])) |> Map.put(:action, :delete)

  # An embedded one the editor removed (`on_replace: :update`, a Blueprint's
  # default, takes `nil`) stays removed if the saved row is the one they
  # removed.
  defp remove_one(_assoc, nil, _base), do: :keep

  defp remove_one(%Ecto.Embedded{on_replace: :update}, saved, %_{} = base),
    do: if(Ecto.primary_key(saved) == Ecto.primary_key(base), do: nil, else: :keep)

  defp remove_one(%{on_replace: on_replace}, _saved, _base) when on_replace in [:raise, :update], do: :keep
  defp remove_one(_assoc, _saved, _base), do: nil

  # The editor's row onto the saved one: its changes, over the saved values;
  # with `edits`, the fields they record.
  defp onto(held, saved, nil), do: onto(held, saved)

  defp onto(held, saved, edits),
    do: with_typed(held, saved, Map.get(edits.typed, SubformHelpers.row_key(held), MapSet.new()))

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
  # its own, holding what the editor's form showed, typed values that
  # didn't cast and their errors too.
  defp as_new(entry) do
    entry
    |> applied()
    |> new_struct()
    |> Changeset.change()
    |> Map.put(:action, :insert)
    |> SubformHelpers.new_row()
    |> typed(entry)
  end

  defp new_struct(%row_schema{} = row) do
    row = Enum.reduce(row_schema.__schema__(:primary_key), row, &Map.put(&2, &1, nil))
    # An embedded row has no state
    row = if Map.has_key?(row, :__meta__), do: put_in(row.__meta__.state, :built), else: row

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
