defmodule BrandoAdmin.Components.Form.Input.Blocks.BlockRenderer do
  use Surface.LiveComponent
  use Phoenix.HTML

  alias BrandoAdmin.Components.Form.Input.Blocks

  prop blocks, :list, required: true
  prop block_forms, :list, required: true
  prop base_form, :form, required: true
  prop data_field, :atom, required: true
  prop insert_index, :integer
  prop insert_block, :event, required: true
  prop insert_section, :event, required: true
  prop insert_datasource, :event, required: true
  prop duplicate_block, :event, required: true
  prop show_module_picker, :event, required: true
  prop uploads, :any
  prop templates, :any
  prop type, :string, default: "root"
  prop uid, :string

  @doc "If sections should be visible in the module picker"
  prop hide_sections, :boolean

  data block_count, :integer

  def update(assigns, socket) do
    # TODO: Only count on initial render, then trigger a count from
    # "insert_block", "delete_block", "duplicate_block", "insert_section", "insert_datasource" etc?

    block_count =
      assigns.block_forms
      |> Enum.map(&input_value(&1, :marked_as_deleted))
      |> Enum.reject(&(&1 == true))
      |> Enum.count()

    {:ok,
     socket
     |> assign(assigns)
     |> assign(block_count: block_count)}
  end

  def render(assigns) do
    ~F"""
    <div
      id={"#{@id}-blocks-wrapper"}
      class="blocks-wrapper"
      phx-hook="Brando.SortableBlocks"
      data-blocks-wrapper-type={@type}>

      <Blocks.ModulePicker
        id={"#{@id}-module-picker"}
        insert_block={@insert_block}
        insert_section={@insert_section}
        insert_datasource={@insert_datasource}
        insert_index={@insert_index}
        hide_sections={@hide_sections} />

      {#if @block_count == 0}

        <div class="blocks-empty-instructions">
          {gettext "Click the plus to start adding content blocks"}
          {#if @templates}
            <br>{gettext "or get started with a prefab'ed template"}:<br>
            <div class="blocks-templates">
              {#for template <- @templates}
                <button type="button" :on-click="use_template" phx-value-id={template.id}>
                  {template.name}<br>
                  <small>{template.instructions}</small>
                </button>
              {/for}
            </div>
          {/if}
        </div>
        <Blocks.Plus
          index={0}
          click={@show_module_picker} />
      {/if}

      {#for {block_form, index} <- Enum.with_index(@block_forms)}
        <Blocks.DynamicBlock
          uploads={@uploads}
          index={index}
          data_field={@data_field}
          base_form={@base_form}
          block_count={@block_count}
          block={block_form}
          belongs_to={@type}
          insert_block={@show_module_picker}
          duplicate_block={@duplicate_block} />
      {/for}
    </div>
    """
  end

  def handle_event(
        "use_template",
        %{"id" => template_id},
        %{assigns: %{templates: templates, base_form: form, data_field: data_field}} = socket
      ) do
    changeset = form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    template = Enum.find(templates, &(&1.id == String.to_integer(template_id)))

    updated_changeset = Ecto.Changeset.put_change(changeset, data_field, template.data)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event(
        "blocks:reorder",
        %{"order" => order_indices, "type" => "root"},
        %{assigns: %{base_form: form, data_field: data_field}} = socket
      ) do
    changeset = form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    blocks = Ecto.Changeset.get_field(changeset, data_field)

    new_data = Enum.map(order_indices, &Enum.at(blocks, &1))
    updated_changeset = Ecto.Changeset.put_change(changeset, data_field, new_data)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  def handle_event(
        "blocks:reorder",
        %{"order" => order_indices, "type" => "container"},
        %{assigns: %{base_form: form, uid: uid, blocks: blocks, data_field: data_field}} = socket
      ) do
    changeset = form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    ordered_blocks = Enum.map(order_indices, &Enum.at(blocks, &1))

    updated_changeset =
      Brando.Villain.update_block_in_changeset(
        changeset,
        data_field,
        uid,
        %{
          data: %{blocks: ordered_blocks}
        }
      )

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end
end
