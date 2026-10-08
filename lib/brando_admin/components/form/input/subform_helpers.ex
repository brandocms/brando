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
      entries when is_list(entries) -> Enum.reject(entries, &removed?/1)
      entry -> entry
    end
  end

  # A saved row the editor removed stays in the relation as a changeset
  # marked for removal. It is not a row any more: the form doesn't show it,
  # and writing it back with `put_assoc` raises ("cannot replace related").
  # Leaving it out is enough, as `put_entries/3` derives the removal again
  # from the relation's data.
  defp removed?(%Changeset{action: action}) when action in [:replace, :delete], do: true
  defp removed?(_entry), do: false

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

  ## Rows by identity
  #
  # The browser names a row by its key, not its position: positions move
  # under it when a row is added or removed before the click arrives. A saved
  # row's key is its id. A new row's is a key given to it when it was added
  # (`new_row/1`), which the row renders back as a hidden `_key` input
  # (`new_row_key/1`), so it survives the form being rebuilt from the
  # browser's fields.

  @key "_key"

  @doc "The row's key: `id-…` for a saved row, its `_key` for a new one, or nil."
  def row_key(%Phoenix.HTML.Form{source: source}), do: row_key(source)
  def row_key(%Changeset{data: data, params: params}), do: saved_key(data) || new_key(params)
  def row_key(%{} = entry), do: saved_key(entry)
  def row_key(_entry), do: nil

  @doc """
  The keys of the relation's rows, in the order the form renders them. For
  rows rendered without their own changeset (`inputs_for_poly`), look the key
  up by the row's index.
  """
  def row_keys(%Changeset{} = changeset, field_name),
    do: changeset |> current_entries(field_name) |> Enum.map(&row_key/1)

  @doc "Whether `key` is a new row's, which the row renders as its hidden `_key` input."
  def new_key?("new-" <> _), do: true
  def new_key?(_key), do: false

  @doc "A new row's key, to render as its hidden `_key` input; nil for a saved row."
  def new_row_key(%Phoenix.HTML.Form{source: %Changeset{data: data, params: params}}),
    do: if(saved_key(data), do: nil, else: new_key(params))

  def new_row_key(_form), do: nil

  defp saved_key(%{id: id}) when not is_nil(id), do: "id-#{id}"
  defp saved_key(_data), do: nil

  defp new_key(%{@key => key}) when is_binary(key) and key != "", do: key
  defp new_key(_params), do: nil

  @doc """
  A row to add: a changeset of `entry` (a struct or a changeset) with a key
  of its own. See `new_row/3` for a map of attributes.
  """
  def new_row(%Changeset{} = changeset),
    do: %{changeset | params: Map.put(changeset.params || %{}, @key, "new-" <> Brando.Utils.generate_uid())}

  def new_row(%_{} = entry), do: entry |> Changeset.change() |> new_row()

  @doc """
  A row to add to the relation `field_name` of `changeset`. A map of
  attributes (a subform's `default %{…}`) becomes a changeset of the
  related schema first, as `put_assoc`/`put_embed` would make it, so it has
  somewhere to keep its key.
  """
  def new_row(%Changeset{} = changeset, field_name, %{} = attrs) when not is_struct(attrs) do
    changeset
    |> related(field_name)
    |> struct()
    |> Changeset.change(attrs)
    |> new_row()
  end

  def new_row(_changeset, _field_name, entry), do: new_row(entry)

  defp related(%Changeset{data: %module{}}, field_name) do
    %{related: related} = module.__schema__(:association, field_name) || module.__schema__(:embed, field_name)
    related
  end

  @doc "Removes the row with `key` from the subform field."
  def remove_subentry(socket, key), do: send_op(socket, {:delete, key})

  @doc "Puts the rows named by `keys` in that order."
  def sequenced_subform(socket, keys, opts \\ []),
    do: send_op(socket, {:reorder, Enum.map(keys, &to_string/1), Keyword.get(opts, :sequence, false)})

  @doc "Appends entries to the subform field, keeping pending sibling input."
  def append_subentries(socket, new_entries) do
    send_op(socket, {:append, Enum.map(List.wrap(new_entries), &new_row_for(socket, &1))})
  end

  @doc """
  Inserts an entry above the row with `key`, or at `index` when the row has
  no key, keeping pending sibling input.
  """
  def insert_subentry(socket, key, index, new_entry) do
    index = if is_binary(index), do: String.to_integer(index), else: index
    send_op(socket, {:insert, blank_to_nil(key), index, new_row_for(socket, new_entry)})
  end

  defp new_row_for(socket, entry),
    do: new_row(socket.assigns.field.form.source, socket.assigns.subform.name, entry)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(key), do: key

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
  # Removals, replacements and reorders name rows by key, so they reach the
  # row the editor meant wherever it is by then; a row that is already gone (a
  # double click on ×) is left alone rather than another removed in its place.
  #
  # The form doesn't ask the browser to validate afterwards. It used to, for
  # adds: the browser answered with the form's fields as it showed them, and
  # when a second add was already on its way, that answer still had one row
  # fewer and the form, rebuilt from it, dropped the newest row again. The new
  # row is validated with the next change the editor makes, like any other.

  @typedoc "An operation on a relation's list of entries. Rows are named by `row_key/1`."
  @type op ::
          {:append, [term()]}
          | {:insert, String.t() | nil, non_neg_integer(), term()}
          | {:replace, String.t(), term()}
          | {:delete, String.t()}
          | {:reorder, [String.t()], boolean()}
          | {:update, ([term()] -> [term()])}

  @doc """
  Applies `op` to `entries`, the relation's current entries. Returns the new
  list, or `:stale` when the row it names is not there any more.
  """
  @spec apply_op([term()], op()) :: [term()] | :stale
  def apply_op(entries, {:append, new_entries}), do: entries ++ List.wrap(new_entries)

  # Above the named row; without one, at the position, past the end appending
  def apply_op(entries, {:insert, key, index, entry}) do
    at = (key && find_row(entries, key)) || min(index, length(entries))
    List.insert_at(entries, at, entry)
  end

  def apply_op(entries, {:replace, key, entry}),
    do: with_row(entries, key, &List.replace_at(entries, &1, entry))

  def apply_op(entries, {:delete, key}), do: with_row(entries, key, &List.delete_at(entries, &1))

  # Named rows in the given order; a row the browser didn't name (added since)
  # keeps its place after them, and a name that matches nothing is skipped.
  def apply_op(entries, {:reorder, keys, sequence?}) do
    by_key = Map.new(entries, &{row_key(&1), &1})
    named = keys |> Enum.map(&Map.get(by_key, &1)) |> Enum.reject(&is_nil/1)

    if named == [] do
      :stale
    else
      (named ++ Enum.reject(entries, &(&1 in named)))
      |> Enum.with_index()
      |> Enum.map(fn
        {entry, idx} when sequence? -> Changeset.change(entry, %{sequence: idx})
        {entry, _idx} -> entry
      end)
    end
  end

  def apply_op(entries, {:update, fun}) when is_function(fun, 1), do: fun.(entries)
  def apply_op(_entries, _op), do: :stale

  defp find_row(_entries, nil), do: nil
  defp find_row(entries, key), do: Enum.find_index(entries, &(row_key(&1) == key))

  defp with_row(entries, key, fun) do
    case find_row(entries, key) do
      nil -> :stale
      index -> fun.(index)
    end
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
end
