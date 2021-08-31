defmodule BrandoAdmin.Components.Form.Subform do
  # use Surface.Component
  use Surface.LiveComponent
  use Phoenix.HTML

  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.FieldBase

  import Brando.Gettext

  prop subform, :any
  prop form, :any
  prop blueprint, :any
  prop uploads, :any

  def mount(socket) do
    {:ok, socket}
  end

  def render(assigns) do
    ~F"""
    <fieldset>
      {#if @subform.cardinality == :one}
        <FieldBase
          blueprint={@blueprint}
          field={@subform.field}
          class={subform: true}
          form={@form}>
          {#for sub_form <- inputs_for(@form, @subform.field)}
            <div class="subform-entry">
              {#for input <- @subform.sub_fields}
                <Input
                  id={"#{@form.id}-#{sub_form.id}-input-one-#{input.name}"}
                  input={input}
                  form={sub_form}
                  blueprint={@blueprint}
                  uploads={@uploads} />
              {/for}
            </div>
          {/for}
        </FieldBase>
      {#else}
        <FieldBase
          blueprint={@blueprint}
          field={@subform.field}
          class={subform: true}
          form={@form}>
          <div
            id={"#{@form.id}-#{@subform.field}-sortable"}
            phx-hook="Brando.SubFormSortable">
            {#if Enum.empty?(inputs_for(@form, @subform.field))}
              <input type="hidden" name={"#{@form.name}[#{@subform.field}]"} value="" />
              <div class="subform-empty">&rarr; No associated entries</div>
            {/if}
            {#for {sub_form, index} <- Enum.with_index(inputs_for(@form, @subform.field))}
              <div
                class={"subform-entry", inline: @subform.style == :inline}
                data-id={index}>
                <div class="subform-tools">
                  <button type="button" class="subform-handle">
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path class="s" d="M12 2l4.243 4.243-1.415 1.414L12 4.828 9.172 7.657 7.757 6.243 12 2zM2 12l4.243-4.243 1.414 1.415L4.828 12l2.829 2.828-1.414 1.415L2 12zm20 0l-4.243 4.243-1.414-1.415L19.172 12l-2.829-2.828 1.414-1.415L22 12zm-10 2a2 2 0 1 1 0-4 2 2 0 0 1 0 4zm0 8l-4.243-4.243 1.415-1.414L12 19.172l2.828-2.829 1.415 1.414L12 22z" fill="rgba(5,39,82,1)"/></svg>
                  </button>
                  <button
                    :on-click="remove_subentry"
                    phx-value-index={index}
                    type="button"
                    class="subform-delete">
                    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path class="s" d="M17 6h5v2h-2v13a1 1 0 0 1-1 1H5a1 1 0 0 1-1-1V8H2V6h5V3a1 1 0 0 1 1-1h8a1 1 0 0 1 1 1v3zm1 2H6v12h12V8zm-4.586 6l1.768 1.768-1.414 1.414L12 15.414l-1.768 1.768-1.414-1.414L10.586 14l-1.768-1.768 1.414-1.414L12 12.586l1.768-1.768 1.414 1.414L13.414 14zM9 4v2h6V4H9z" fill="rgba(5,39,82,1)"/></svg>
                  </button>
                </div>
                {#for input <- @subform.sub_fields}
                  <Input
                    id={"#{@id}-#{sub_form.id}-input-#{input.name}"}
                    input={input}
                    form={sub_form}
                    blueprint={@blueprint}
                    uploads={@uploads} />
                {/for}
              </div>
            {/for}
          </div>
          <button
            id={"#{@form.id}-#{@subform.field}-add-entry"}
            type="button"
            class="add-subentry"
            phx-hook="Brando.SubEntryAddButton">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M18 15l-.001 3H21v2h-3.001L18 23h-2l-.001-3H13v-2h2.999L16 15h2zm-7 3v2H3v-2h8zm10-7v2H3v-2h18zm0-7v2H3V4h18z" fill="rgba(252,245,243,1)"/></svg>
            {gettext("Add entry")}
          </button>
        </FieldBase>
      {/if}
    </fieldset>
    """
  end

  def handle_event("add_subentry", _, socket) do
    changeset = socket.assigns.form.source
    default = socket.assigns.subform.default
    field_name = socket.assigns.subform.field

    module = changeset.data.__struct__
    form_id = "#{module.__naming__.singular}_form"

    updated_field =
      changeset
      |> Ecto.Changeset.get_field(field_name)
      |> Kernel.++([default])

    updated_changeset =
      case Enum.find(socket.assigns.blueprint.relations, &(&1.name == field_name)) do
        %{type: :has_many} ->
          # assoc
          Ecto.Changeset.put_assoc(changeset, field_name, updated_field)

        _ ->
          # embed
          Ecto.Changeset.put_embed(changeset, field_name, updated_field)
      end

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event("remove_subentry", %{"index" => index}, socket) do
    field_name = socket.assigns.subform.field
    changeset = socket.assigns.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__.singular}_form"

    updated_entries =
      changeset
      |> Ecto.Changeset.get_field(field_name, [])
      |> List.delete_at(String.to_integer(index))

    updated_changeset =
      case Enum.empty?(updated_entries) do
        true ->
          put_in(changeset, [Access.key(:changes), Access.key(field_name)], [])

        false ->
          Ecto.Changeset.put_embed(changeset, field_name, updated_entries)
      end

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event("force_validate", _, socket) do
    field_name = socket.assigns.subform.field
    event_id = "#{socket.assigns.form.id}-#{field_name}-add-entry"
    {:noreply, push_event(socket, "b:validate:#{event_id}", %{})}
  end

  def handle_event("sequenced_subform", %{"ids" => order_indices}, socket) do
    field_name = socket.assigns.subform.field
    changeset = socket.assigns.form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__.singular}_form"

    entries = Ecto.Changeset.get_field(changeset, field_name)
    sorted_entries = Enum.map(order_indices, &Enum.at(entries, &1))

    updated_changeset =
      case Enum.find(socket.assigns.blueprint.relations, &(&1.name == field_name)) do
        %{type: :has_many} ->
          # assoc
          Ecto.Changeset.put_assoc(changeset, field_name, sorted_entries)

        _ ->
          # embed
          Ecto.Changeset.put_embed(changeset, field_name, sorted_entries)
      end

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end
end
