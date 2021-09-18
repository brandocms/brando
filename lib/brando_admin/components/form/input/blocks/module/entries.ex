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
      phx-hook="Brando.Sortable"
      data-sortable-id={"block_entries"}
      data-sortable-handle=".move"
      data-sortable-selector="[data-block-type=module_entry]">
      {#for {entry_form, idx} <- Enum.with_index(@entry_forms)}
        <EntryBlock
          id={v(entry_form, :uid)}
          block={entry_form}
          base_form={@base_form}
          data_field={@data_field}
          entry_template={@entry_template}
          index={idx}
          block_count={Enum.count(@entry_forms)}
          insert_block=""
          duplicate_block=""
        />
      {/for}

      <button class="add-module-entry" type="button" :on-click="add_entry">
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

  def prepare_entry_template(entry_template) do
    require Logger
    Logger.error(inspect(entry_template))
  end
end
