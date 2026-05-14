defmodule BrandoAdmin.Components.Form.Input.SubformHelpers do
  @moduledoc """
  Shared event handling helpers for subform components (Vars, Globals, PageVars).
  """

  @doc "Removes a subentry at the given index from the subform field."
  def remove_subentry(socket, index) do
    field_name = socket.assigns.subform.name
    changeset = socket.assigns.field.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    updated_entries =
      changeset
      |> Ecto.Changeset.get_field(field_name, [])
      |> List.delete_at(String.to_integer(index))

    updated_changeset = Ecto.Changeset.put_change(changeset, field_name, updated_entries)

    Phoenix.LiveView.send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, socket}
  end

  @doc "Reorders subform entries according to the given index order."
  def sequenced_subform(socket, order_indices) do
    field_name = socket.assigns.subform.name
    changeset = socket.assigns.field.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    entries = Ecto.Changeset.get_field(changeset, field_name)
    sorted_entries = Enum.map(order_indices, &Enum.at(entries, &1))

    updated_changeset = Ecto.Changeset.put_change(changeset, field_name, sorted_entries)

    Phoenix.LiveView.send_update(BrandoAdmin.Components.Form,
      id: form_id,
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, socket}
  end
end
