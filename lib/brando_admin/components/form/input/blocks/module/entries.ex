defmodule BrandoAdmin.Components.Form.Input.Blocks.Module.Entries do
  use BrandoAdmin, :live_component
  # use Phoenix.HTML
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.Input.Blocks.Module.EntryBlock
  import Brando.Gettext

  # prop block_data, :form, required: true
  # prop base_form, :form, required: true
  # prop data_field, :atom, required: true
  # prop entry_template, :map, required: true
  # prop uid, :string, required: true

  # data entry_forms, :list

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:entry_count, Enum.count(assigns.block_data.data.entries))}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"block-#{@uid}-module-entries"}
      class="module-entries"
      phx-hook="Brando.SortableBlocks"
      data-blocks-wrapper-type="module_entry"
    >
      <Form.inputs_for_poly :let={entry_form} field={@block_data[:entries]}>
        <.live_component
          module={EntryBlock}
          id={entry_form[:uid].value}
          block={entry_form}
          base_form={@base_form}
          data_field={@data_field}
          entry_template={@entry_template}
          belongs_to="module_entry"
          module_id={@module_id}
          index={entry_form.index}
          block_count={@entry_count}
          insert_module=""
          duplicate_block=""
        />
      </Form.inputs_for_poly>

      <button
        type="button"
        class="add-module-entry"
        phx-click={JS.push("add_entry", target: @myself)}
        phx-page-loading
      >
        <%= gettext("Add") %> [<%= @entry_template.name %>]
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

    entries = block_data[:entries].value
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
      action: :update_changeset,
      changeset: updated_changeset
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
    blocks = block_data[:entries].value

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
      action: :update_changeset,
      changeset: updated_changeset
    )

    {:noreply, socket}
  end
end
