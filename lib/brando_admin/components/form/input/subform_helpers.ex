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
    field_name = socket.assigns.subform.name
    changeset = socket.assigns.field.form.source

    updated_entries =
      changeset
      |> current_entries(field_name)
      |> List.delete_at(String.to_integer(index))

    update_form(socket, changeset, field_name, updated_entries)
  end

  @doc "Reorders subform entries according to the given index order."
  def sequenced_subform(socket, order_indices) do
    field_name = socket.assigns.subform.name
    changeset = socket.assigns.field.form.source
    entries = current_entries(changeset, field_name)

    update_form(socket, changeset, field_name, Enum.map(order_indices, &Enum.at(entries, &1)))
  end

  @doc "Appends entries to the subform field, keeping pending sibling input."
  def append_subentries(socket, new_entries) do
    field_name = socket.assigns.subform.name
    changeset = socket.assigns.field.form.source
    entries = current_entries(changeset, field_name)

    update_form(socket, changeset, field_name, entries ++ List.wrap(new_entries))
  end

  defp update_form(socket, changeset, field_name, entries) do
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    Phoenix.LiveView.send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: put_entries(changeset, field_name, entries)
    )

    {:noreply, socket}
  end
end
