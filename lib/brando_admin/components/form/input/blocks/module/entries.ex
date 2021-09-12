defmodule BrandoAdmin.Components.Form.Input.Blocks.Module.Entries do
  use Surface.LiveComponent
  use Phoenix.HTML
  alias Surface.Components.Form.HiddenInput
  alias BrandoAdmin.Components.Form.Input.Blocks
  import BrandoAdmin.Components.Form.Input.Blocks.Utils

  prop block_data, :form, required: true
  prop base_form, :form, required: true
  prop data_field, :atom, required: true
  prop entry_template, :map, required: true
  prop uid, :string, required: true

  def v(form, field), do: input_value(form, field)

  def update(assigns, socket) do
    entries = input_value(assigns.block_data, :entries)

    require Logger
    Logger.error("==> entries: #{inspect(entries, pretty: true)}")
    Logger.error("==> entry_template: #{inspect(assigns.entry_template, pretty: true)}")

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:entries, entries)}
  end

  def render(assigns) do
    ~F"""
    <div class="module-entries">
      {#for entry <- @entries}
        ENTRY: {entry.uid}<br>
      {/for}

      <button type="button" :on-click="add_entry">
        Add new entry
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
    form_id = "#{module.__naming__.singular}_form"

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

    require Logger
    Logger.error(inspect(updated_entries, pretty: true))

    updated_changeset =
      Brando.Villain.update_block_in_changeset(
        changeset,
        data_field,
        block_uid,
        %{data: %{entries: updated_entries}}
      )

    require Logger
    Logger.error(inspect(updated_changeset, pretty: true))

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
