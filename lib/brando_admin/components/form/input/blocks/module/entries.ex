defmodule BrandoAdmin.Components.Form.Input.Blocks.Module.Entries do
  use Surface.LiveComponent
  use Phoenix.HTML
  alias BrandoAdmin.Components.Form.Input.Blocks.Module.EntryBlock
  import BrandoAdmin.Components.Form.Input.Blocks.Utils

  prop block_data, :form, required: true
  prop base_form, :form, required: true
  prop data_field, :atom, required: true
  prop entry_template, :map, required: true
  prop uid, :string, required: true

  data entry_forms, :list

  def v(form, field), do: input_value(form, field)

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:entry_forms, inputs_for_blocks(assigns.block_data, :entries))}
  end

  def render(assigns) do
    ~F"""
    <div
      id={"#{@uid}-module-entries"}
      class="module-entries"
      phx-hook="Brando.SortableBlocks"
      data-blocks-wrapper-type="module_entry">
      {#for {entry_form, idx} <- Enum.with_index(@entry_forms)}
        <EntryBlock
          id={v(entry_form, :uid)}
          block={entry_form}
          base_form={@base_form}
          data_field={@data_field}
          entry_template={@entry_template}
          belongs_to="module_entry"
          index={idx}
          block_count={Enum.count(@entry_forms)}
          insert_block=""
          duplicate_block=""
        />
      {/for}

      <button class="add-module-entry" type="button" :on-click="add_entry" phx-page-loading>
        Add new entry [{@entry_template.name}]
      </button>
    </div>
    """
  end

  def handle_event(
        "add_entry",
        _,
        %{
          assigns: %{
            entry_template: entry_template,
            data_field: data_field,
            block_data: block_data,
            base_form: form,
            uid: block_uid
          }
        } = socket
      ) do
    changeset = form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    generated_uid = Brando.Utils.generate_uid()

    refs_with_generated_uids = Brando.Villain.add_uid_to_refs(entry_template.refs)

    new_entry = %Brando.Content.Module.Entry{
      type: "module_entry",
      data: %Brando.Content.Module.Entry.Data{
        vars: entry_template.vars,
        refs: refs_with_generated_uids
      },
      uid: generated_uid
    }

    entries = input_value(block_data, :entries)
    updated_entries = entries ++ [new_entry]

    updated_changeset =
      Brando.Villain.update_block_in_changeset(
        changeset,
        data_field,
        block_uid,
        %{data: %{entries: updated_entries}}
      )

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event(
        "blocks:reorder",
        %{"order" => order_indices, "type" => "module_entry"},
        %{assigns: %{base_form: form, uid: uid, data_field: data_field, block_data: block_data}} =
          socket
      ) do
    changeset = form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"
    blocks = input_value(block_data, :entries)

    ordered_blocks = Enum.map(order_indices, &Enum.at(blocks, &1))

    updated_changeset =
      Brando.Villain.update_block_in_changeset(
        changeset,
        data_field,
        uid,
        %{
          data: %{entries: ordered_blocks}
        }
      )

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end
end
