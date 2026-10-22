defmodule BrandoAdmin.Components.Form.RelationRows do
  @moduledoc false
  # The has_many, has_one and many_to_many relations of an entry form. They
  # don't ship between editors as field changes (`Form.sync_fields/1`), so
  # another editor's save (`Form.take_saved_entry/1`) is where they meet: a
  # form keeps the relations its editor changed (`carry/3`) and takes the
  # saved rows in the rest. Rows compare by content (`rows/2`): the rows a
  # form builds again from the browser's params are new structs.

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
  the rows a form built for the same choices compare equal. Rows removed (or
  marked to be) are left out; a many_to_many row is the entry it names.
  """
  def rows(%Changeset{data: %schema{} = data} = changeset, field) do
    rows =
      case Map.fetch(changeset.changes, field) do
        {:ok, rows} ->
          for %Changeset{action: action} = row <- List.wrap(rows),
              action not in [:replace, :delete],
              do: Changeset.apply_changes(row)

        :error ->
          Map.get(data, field)
      end

    case rows do
      %Association.NotLoaded{} ->
        :not_loaded

      rows ->
        assoc = schema.__schema__(:association, field)
        for row <- List.wrap(rows), Map.get(row, :marked_as_deleted) != true, do: content(assoc, row)
    end
  end

  defp content(%Association.ManyToMany{}, row), do: Ecto.primary_key(row)

  defp content(%{related_key: owner_key}, %row_schema{} = row) do
    skip = [owner_key, :inserted_at, :updated_at | row_schema.__schema__(:primary_key)]
    Map.take(row, row_schema.__schema__(:fields) -- skip)
  end

  @doc """
  The relation as `previous` holds it, put onto `saved`: the rows it added,
  and the saved ones it changed or removed that the save kept. A many_to_many
  keeps every entry it names. Rows an asset delivery applied into the data
  (`Form.commit_entry_field_asset/5`) count as its changes.
  """
  def carry(%Changeset{data: %schema{} = data} = saved, %Changeset{} = previous, field) do
    assoc = schema.__schema__(:association, field)
    current = Map.get(data, field)

    edit =
      case Map.fetch(previous.changes, field) do
        {:ok, edit} -> edit
        :error -> previous.data |> Map.get(field) |> as_changes(current)
      end

    cond do
      not Ecto.assoc_loaded?(current) -> %{saved | changes: Map.put(saved.changes, field, edit)}
      assoc.cardinality == :one -> carry_one(saved, field, edit, current)
      true -> Changeset.put_assoc(saved, field, kept_rows(assoc, current, edit))
    end
  end

  # Rows held in the data, as changes to the saved rows: a row with no
  # changes is one `put_assoc/3` leaves out.
  defp as_changes(nil, _current), do: nil
  defp as_changes(rows, current) when is_list(rows), do: Enum.map(rows, &as_change(&1, saved_rows(current)))
  defp as_changes(row, current), do: as_change(row, saved_rows(current))

  defp saved_rows(current) do
    if Ecto.assoc_loaded?(current),
      do: current |> List.wrap() |> Map.new(&{Ecto.primary_key(&1), &1}),
      else: %{}
  end

  defp as_change(%schema{__meta__: %{state: :loaded}} = row, saved) do
    case Map.fetch(saved, Ecto.primary_key(row)) do
      {:ok, saved_row} ->
        changes = for f <- schema.__schema__(:fields), Map.get(row, f) != Map.get(saved_row, f), do: {f, Map.get(row, f)}
        saved_row |> Changeset.change(changes) |> Map.put(:action, :update)

      :error ->
        row |> Changeset.change() |> Map.put(:action, :update)
    end
  end

  defp as_change(row, _saved), do: row |> Changeset.change() |> Map.put(:action, :insert)

  # An entry linked is not a row the save could have removed.
  defp kept_rows(%Association.ManyToMany{}, _saved, rows), do: Enum.reject(rows, &(&1.action == :replace))

  defp kept_rows(assoc, saved, rows) do
    keys = MapSet.new(saved, &Ecto.primary_key/1)

    rows =
      Enum.filter(rows, fn %Changeset{action: action, data: row} ->
        action == :insert or (action != :replace and MapSet.member?(keys, Ecto.primary_key(row)))
      end)

    # A list whose rows can't be replaced keeps the saved ones it doesn't hold.
    if assoc.on_replace == :raise do
      held = MapSet.new(rows, &Ecto.primary_key(&1.data))
      rows ++ Enum.reject(saved, &MapSet.member?(held, Ecto.primary_key(&1)))
    else
      rows
    end
  end

  # A row removed stays removed, and a new one stays; a change to a row the
  # save replaced with another goes.
  defp carry_one(saved, field, edit, current) do
    case edit do
      %Changeset{action: action} when action in [:replace, :delete] ->
        Changeset.put_assoc(saved, field, nil)

      nil ->
        Changeset.put_assoc(saved, field, nil)

      %Changeset{action: :insert} ->
        Changeset.put_assoc(saved, field, edit)

      %Changeset{data: row} ->
        if current && Ecto.primary_key(current) == Ecto.primary_key(row),
          do: Changeset.put_assoc(saved, field, edit),
          else: saved
    end
  end
end
