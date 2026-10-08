defmodule BrandoAdmin.Components.Form.Input.SubformHelpers do
  @moduledoc """
  Shared event handling helpers for subform components (Vars, Globals, PageVars).

  ## Reading a relation before rewriting it

  These handlers all rebuild a relation's list (drop a row, append a row,
  reorder). They MUST read it with `current_entries/2` — never
  `Ecto.Changeset.get_field/3`.

  `get_field/3` returns *applied structs*. The pending value survives into the
  struct, so the read looks correct, but writing structs back produces child
  changesets with **no changes** — the struct simply becomes the new `data`.
  Ecto then has nothing to write, so a row the user had typed into but not yet
  blurred silently reverts on save. Measured:

      get_field  -> put_change  =>  [{"one", %{}}]                 persists "orig"
      get_assoc  -> put_assoc   =>  [{"one", %{value: "PENDING"}}]  persists "PENDING"

  This is the same failure mode as the ref media FKs: a value that lives in
  `data` rather than in `changes` never reaches SQL. It is the Append Changeset
  pattern in AGENTS.md, and the reason it insists on `get_assoc`.
  """

  alias Ecto.Changeset

  @doc """
  The relation's current child CHANGESETS, pending edits intact.

  Dispatches on the schema so the same helpers serve both assoc-backed and
  embed-backed subforms (Vars are assocs, some Globals/PageVars are embeds).
  """
  def current_entries(%Changeset{} = changeset, field_name) do
    case relation_kind(changeset, field_name) do
      :assoc -> Changeset.get_assoc(changeset, field_name)
      :embed -> Changeset.get_embed(changeset, field_name)
    end
    |> case do
      %Ecto.Association.NotLoaded{} -> []
      nil -> []
      entries -> entries
    end
  end

  @doc "Writes a rebuilt child list back onto the relation, assoc or embed."
  def put_entries(%Changeset{} = changeset, field_name, entries) do
    case relation_kind(changeset, field_name) do
      :assoc -> Changeset.put_assoc(changeset, field_name, entries)
      :embed -> Changeset.put_embed(changeset, field_name, entries)
    end
  end

  defp relation_kind(%Changeset{data: %module{}}, field_name) do
    if module.__schema__(:association, field_name), do: :assoc, else: :embed
  end

  @doc "Removes a subentry at the given index from the subform field."
  def remove_subentry(socket, index) do
    index = if is_binary(index), do: String.to_integer(index), else: index
    send_op(socket, {:delete, index, seen_count(socket)})
  end

  @doc "Reorders subform entries according to the given index order."
  def sequenced_subform(socket, order_indices) do
    send_op(socket, {:reorder, order_indices, seen_count(socket), false})
  end

  @doc "Appends entries to the subform field, keeping pending sibling input."
  def append_subentries(socket, new_entries) do
    send_op(socket, {:append, new_entries})
  end

  @doc "Inserts an entry at the given index, keeping pending sibling input."
  def insert_subentry(socket, index, new_entry) do
    index = if is_binary(index), do: String.to_integer(index), else: index
    send_op(socket, {:insert, index, new_entry})
  end

  ## Changing the list
  #
  # A subform holds the form's changeset as it was when the form last rendered
  # it. Rebuilding the list from that copy and handing the whole changeset back
  # loses work: a second click on "Add entry" that arrives before the form has
  # re-rendered the subform builds on the same stale copy, and the second
  # result overwrites the first — one row is lost. So subforms send the form an
  # operation instead, and the form applies it to its own changeset, which is
  # always the latest (`BrandoAdmin.Components.Form`, `:update_entries`).
  #
  # Adds are cumulative: each one appends to whatever the list is by then.
  # Removing and reordering name rows by position, so they apply only to the
  # list the editor saw; when it has changed in between (a double click on ×
  # whose first click already removed the row), they do nothing rather than
  # remove or reorder the wrong rows.
  #
  # The form doesn't ask the browser to validate afterwards. It used to, for
  # adds: the browser answered with the form's fields as it showed them, and
  # when a second add was already on its way, that answer still had one row
  # fewer and the form, rebuilt from it, dropped the newest row again. The new
  # row is validated with the next change the editor makes, like any other.

  @typedoc "An operation on a relation's list of entries."
  @type op ::
          {:append, term() | [term()]}
          | {:insert, non_neg_integer(), term()}
          | {:replace, non_neg_integer(), term()}
          | {:delete, non_neg_integer(), non_neg_integer()}
          | {:reorder, [non_neg_integer()], non_neg_integer(), boolean()}
          | {:update, ([term()] -> [term()])}

  @doc """
  Applies `op` to `entries`, the relation's current entries. Returns the new
  list, or `:stale` when the operation names positions in a list that has
  changed since the editor saw it.
  """
  @spec apply_op([term()], op()) :: [term()] | :stale
  def apply_op(entries, {:append, new_entries}), do: entries ++ List.wrap(new_entries)

  # Past the end appends, as the list may have shrunk since
  def apply_op(entries, {:insert, index, entry}), do: List.insert_at(entries, min(index, length(entries)), entry)

  def apply_op(entries, {:replace, index, entry}),
    do: if_seen(entries, index < length(entries), &List.replace_at(&1, index, entry))

  def apply_op(entries, {:delete, index, seen}),
    do: if_seen(entries, length(entries) == seen and index < seen, &List.delete_at(&1, index))

  def apply_op(entries, {:reorder, indices, seen, sequence?}) do
    permutation? = length(entries) == seen and Enum.sort(indices) == Enum.to_list(0..(seen - 1)//1)
    if_seen(entries, permutation?, &reorder(&1, indices, sequence?))
  end

  def apply_op(entries, {:update, fun}) when is_function(fun, 1), do: fun.(entries)
  def apply_op(_entries, _op), do: :stale

  defp if_seen(entries, true, fun), do: fun.(entries)
  defp if_seen(_entries, false, _fun), do: :stale

  defp reorder(entries, indices, sequence?) do
    indices
    |> Enum.map(&Enum.at(entries, &1))
    |> Enum.with_index()
    |> Enum.map(fn
      {entry, idx} when sequence? -> Changeset.change(entry, %{sequence: idx})
      {entry, _idx} -> entry
    end)
  end

  @doc """
  Sends `op` for the subform's relation to the form that owns the changeset.
  `socket` is the subform component's; the relation is its `subform.name`
  unless `field:` names another.
  """
  def send_op(socket, op, opts \\ []) do
    field_name = Keyword.get_lazy(opts, :field, fn -> socket.assigns.subform.name end)
    module = socket.assigns.field.form.source.data.__struct__

    Phoenix.LiveView.send_update(BrandoAdmin.Components.Form,
      id: "#{module.__naming__().singular}_form",
      action: :update_entries,
      field: field_name,
      op: op
    )

    {:noreply, socket}
  end

  # How many entries the editor saw: the list as this subform last rendered it.
  defp seen_count(socket) do
    socket.assigns.field.form.source
    |> current_entries(socket.assigns.subform.name)
    |> length()
  end
end
