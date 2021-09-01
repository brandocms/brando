defmodule BrandoAdmin.Components.Form.Input.Blocks do
  use Surface.LiveComponent
  use Phoenix.HTML

  import Ecto.Changeset
  import PolymorphicEmbed.HTML.Form
  import BrandoAdmin.Components.Form.Input.Blocks.Utils

  alias Surface.Components.Form.TextInput
  alias Surface.Components.Form.HiddenInput
  alias Brando.Villain
  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Components.Form.Input.Blocks
  alias BrandoAdmin.Components.Form.Input.DynamicBlock
  alias BrandoAdmin.Components.Form.FieldBase
  alias BrandoAdmin.Components.Form.Plus

  prop form, :form
  prop blueprint, :any

  data blocks, :any
  data block_count, :integer
  data insert_index, :integer

  def mount(socket) do
    {:ok, assign(socket, block_count: 0, insert_index: 0)}
  end

  def update(%{input: %{name: name, opts: _opts}} = assigns, socket) do
    blocks = inputs_for_blocks(assigns.form, name)
    block_count = Enum.count(blocks)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:blocks, blocks)
     |> assign(:block_count, block_count)}
  end

  def render(%{input: %{name: name}} = assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      form={@form}
      field={name}>

      {!-- extract to BlockRenderer?
        insert_block
        insert_section
        @insert_index
        @blocks
        duplicate_block
      --}
      <div class="blocks-wrapper">
        <Blocks.ModulePicker
          id={"#{@form.id}-#{name}-module-picker"}
          insert_block="insert_block"
          insert_section="insert_section"
          insert_index={@insert_index} />

        {#if Enum.empty?(@blocks)}
          <div class="blocks-empty-instructions">
            Click the plus to start adding content to your entry!
          </div>
          <Plus
            index={0}
            click="show_module_picker" />
        {/if}

        {#for {block_form, index} <- Enum.with_index(@blocks)}
          <Blocks.DynamicBlock
            index={index}
            base_form={@form}
            block_count={@block_count}
            block={block_form}
            insert_block={"show_module_picker"}
            duplicate_block={"duplicate_block"} />
        {/for}
      </div>
    </FieldBase>
    """
  end

  def handle_event(
        "show_module_picker",
        %{"index" => index_binary},
        %{assigns: %{form: form, input: %{name: name}}} = socket
      ) do
    modal_id = "#{form.id}-#{name}-module-picker"
    Modal.show(modal_id)

    {:noreply, assign(socket, insert_index: index_binary)}
  end

  def handle_event(
        "insert_section",
        %{"index" => index_binary},
        %{assigns: %{form: form, input: %{name: name}}} = socket
      ) do
    modal_id = "#{form.id}-#{name}-module-picker"

    changeset = form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__.singular}_form"

    new_block = %Brando.Blueprint.Villain.Blocks.ContainerBlock{
      type: "container",
      data: %Brando.Blueprint.Villain.Blocks.ContainerBlock.Data{
        class: nil,
        description: nil,
        wrapper: nil,
        blocks: []
      },
      uid: Brando.Utils.generate_uid()
    }

    {index, ""} = Integer.parse(index_binary)

    new_data = List.insert_at(get_blocks_data(changeset), index, new_block)
    updated_changeset = Ecto.Changeset.put_change(changeset, :data, new_data)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    Modal.hide(modal_id)
    selector = "[data-block-uid=\"#{new_block.uid}\"]"

    {:noreply, push_event(socket, "b:scroll_to", %{selector: selector})}
  end

  def handle_event(
        "insert_block",
        %{"index" => index_binary, "module-id" => module_id_binary},
        %{assigns: %{form: form, input: %{name: name}}} = socket
      ) do
    modal_id = "#{form.id}-#{name}-module-picker"

    changeset = form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__.singular}_form"
    module_id = String.to_integer(module_id_binary)

    {:ok, modules} = Villain.list_modules(%{cache: {:ttl, :infinite}})
    module = Enum.find(modules, &(&1.id == module_id))

    # build a module block from module

    new_block = %Brando.Blueprint.Villain.Blocks.ModuleBlock{
      type: "module",
      data: %Brando.Blueprint.Villain.Blocks.ModuleBlock.Data{
        module_id: module_id,
        multi: module.multi,
        vars: module.vars,
        refs: module.refs
      },
      uid: Brando.Utils.generate_uid()
    }

    {index, ""} = Integer.parse(index_binary)

    new_data = List.insert_at(get_blocks_data(changeset), index, new_block)
    updated_changeset = Ecto.Changeset.put_change(changeset, :data, new_data)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    Modal.hide(modal_id)
    selector = "[data-block-uid=\"#{new_block.uid}\"]"

    {:noreply, push_event(socket, "b:scroll_to", %{selector: selector})}
  end

  def handle_event(
        "duplicate_block",
        %{"block_uid" => block_uid},
        %{assigns: %{form: form}} = socket
      ) do
    changeset = form.source
    data = Ecto.Changeset.get_field(changeset, :data)
    source_position = Enum.find_index(data, &(&1.uid == block_uid))

    module = changeset.data.__struct__
    form_id = "#{module.__naming__.singular}_form"

    duplicated_block =
      data
      |> Enum.at(source_position)
      |> Map.put(:uid, Brando.Utils.random_string(13) |> String.upcase())

    new_data = List.insert_at(data, source_position + 1, duplicated_block)
    updated_changeset = Ecto.Changeset.put_change(changeset, :data, new_data)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  defp get_blocks_data(changeset) do
    Ecto.Changeset.get_field(changeset, :data) || []
  end

  defp get_data(changeset, field, type) do
    struct = Ecto.Changeset.apply_changes(changeset)

    case Map.get(struct, field) do
      nil ->
        struct(PolymorphicEmbed.get_polymorphic_module(struct.__struct__, field, type))

      data ->
        data
    end
  end
end
