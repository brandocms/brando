defmodule BrandoAdmin.Components.Form.Input.Blocks do
  use BrandoAdmin, :live_component
  use Phoenix.HTML

  import Ecto.Changeset
  import BrandoAdmin.Components.Form.Input.Blocks.Utils

  alias Brando.Content
  alias Brando.Utils
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.FieldBase
  alias BrandoAdmin.Components.Form.Input.Blocks

  # prop form, :form
  # prop field, :atom
  # prop label, :string
  # prop placeholder, :string
  # prop instructions, :string
  # prop opts, :list, default: []
  # prop current_user, :map
  # prop uploads, :map

  # data blocks, :list
  # data block_forms, :list
  # data insert_index, :integer
  # data data_field, :atom
  # data templates, :any

  def mount(socket) do
    {:ok, assign(socket, insert_index: 0)}
  end

  def update(%{image_drawer_target: target}, socket) do
    {:ok, assign(socket, :image_drawer_target, target)}
  end

  def update(assigns, socket) do
    # TODO: when using input_value here, we sometimes end up with the whole block field as a params map %{"0" => ...}
    blocks = Utils.iv(assigns.form, assigns.field) || []
    block_forms = inputs_for_blocks(assigns.form, assigns.field) || []

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:image_drawer_target, fn ->
       socket.assigns.myself
     end)
     |> assign_new(:templates, fn ->
       if template_namespace = assigns.opts[:template_namespace] do
         {:ok, templates} = Content.list_templates(%{filter: %{namespace: template_namespace}})
         templates
       else
         nil
       end
     end)
     |> assign(:blocks, blocks)
     |> assign(:block_forms, block_forms)
     |> assign(:data_field, assigns.field)}
  end

  def render(assigns) do
    ~H"""
    <div>
      <FieldBase.render
        form={@form}
        field={@field}
        label={@label}
        instructions={@instructions}>
        <Form.image_picker
          id={"image-picker-blocks-#{@form.id}-#{@field}"}
          config_target={"default"}
          z_index={5000}
          select_image={JS.push("select_image", target: @image_drawer_target) |> toggle_drawer("#image-picker-blocks-#{@form.id}-#{@field}")} />
        <.live_component
          module={Blocks.BlockRenderer}
          id={"#{@form.id}-#{@field}-blocks"}
          base_form={@form}
          blocks={@blocks}
          block_forms={@block_forms}
          uploads={@uploads}
          templates={@templates}
          data_field={@data_field}
          insert_index={@insert_index}
          insert_block={JS.push("insert_block", target: @myself) |> hide_modal("##{@form.id}-#{@field}-blocks-module-picker")}
          insert_section={JS.push("insert_section", target: @myself) |> hide_modal("##{@form.id}-#{@field}-blocks-module-picker")}
          insert_datasource={JS.push("insert_datasource", target: @myself) |> hide_modal("##{@form.id}-#{@field}-blocks-module-picker")}
          show_module_picker={JS.push("show_module_picker", target: @myself) |> show_modal("##{@form.id}-#{@field}-blocks-module-picker")}
          duplicate_block={JS.push("duplicate_block", target: @myself)} />
      </FieldBase.render>
    </div>
    """
  end

  def handle_event(
        "show_module_picker",
        %{"index" => index_binary},
        socket
      ) do
    {:noreply, assign(socket, insert_index: index_binary)}
  end

  def handle_event(
        "insert_section",
        %{"index" => index_binary},
        %{assigns: %{form: form}} = socket
      ) do
    changeset = form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    new_block = %Brando.Blueprint.Villain.Blocks.ContainerBlock{
      type: "container",
      data: %Brando.Blueprint.Villain.Blocks.ContainerBlock.Data{
        palette_id: nil,
        blocks: []
      },
      uid: Brando.Utils.generate_uid()
    }

    {index, ""} = Integer.parse(index_binary)

    new_data = List.insert_at(get_blocks_data(changeset), index, new_block)
    updated_changeset = put_change(changeset, :data, new_data)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    selector = "[data-block-uid=\"#{new_block.uid}\"]"

    {:noreply, push_event(socket, "b:scroll_to", %{selector: selector})}
  end

  def handle_event(
        "insert_datasource",
        %{"index" => index_binary},
        %{assigns: %{form: form}} = socket
      ) do
    changeset = form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    new_block = %Brando.Blueprint.Villain.Blocks.DatasourceBlock{
      type: "datasource",
      data: %Brando.Blueprint.Villain.Blocks.DatasourceBlock.Data{},
      uid: Brando.Utils.generate_uid()
    }

    {index, ""} = Integer.parse(index_binary)

    new_data = List.insert_at(get_blocks_data(changeset), index, new_block)
    updated_changeset = put_change(changeset, :data, new_data)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    selector = "[data-block-uid=\"#{new_block.uid}\"]"

    {:noreply, push_event(socket, "b:scroll_to", %{selector: selector})}
  end

  def handle_event(
        "insert_block",
        %{"index" => index_binary, "module-id" => module_id_binary},
        %{assigns: %{form: form}} = socket
      ) do
    changeset = form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"
    module_id = String.to_integer(module_id_binary)

    {:ok, modules} = Content.list_modules(%{cache: {:ttl, :infinite}})
    module = Enum.find(modules, &(&1.id == module_id))

    generated_uid = Brando.Utils.generate_uid()

    refs_with_generated_uids = Brando.Villain.add_uid_to_refs(module.refs)

    # if module.wrapper is true, this is a multi block!
    new_block = %Brando.Blueprint.Villain.Blocks.ModuleBlock{
      type: "module",
      data: %Brando.Blueprint.Villain.Blocks.ModuleBlock.Data{
        module_id: module_id,
        multi: module.wrapper,
        vars: module.vars,
        refs: refs_with_generated_uids
      },
      uid: generated_uid
    }

    {index, ""} = Integer.parse(index_binary)

    new_data = List.insert_at(get_blocks_data(changeset), index, new_block)
    updated_changeset = put_change(changeset, :data, new_data)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    selector = "[data-block-uid=\"#{new_block.uid}\"]"

    {:noreply, push_event(socket, "b:scroll_to", %{selector: selector})}
  end

  def handle_event(
        "duplicate_block",
        %{"block_uid" => block_uid},
        %{assigns: %{form: form, field: data_field}} = socket
      ) do
    changeset = form.source
    data = get_field(changeset, data_field)
    source_position = Enum.find_index(data, &(&1.uid == block_uid))

    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    duplicated_block =
      data
      |> Enum.at(source_position)
      |> replace_uids()

    new_data = List.insert_at(data, source_position + 1, duplicated_block)
    updated_changeset = put_change(changeset, data_field, new_data)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset,
      force_validation: true
    )

    {:noreply, socket}
  end

  defp get_blocks_data(changeset) do
    get_field(changeset, :data) || []
  end

  defp replace_uids(%Brando.Blueprint.Villain.Blocks.ModuleBlock{data: %{refs: refs}} = block) do
    updated_refs = Brando.Villain.add_uid_to_refs(refs)

    block
    |> put_in([Access.key(:uid)], Brando.Utils.generate_uid())
    |> put_in([Access.key(:data), Access.key(:refs)], updated_refs)
  end

  defp replace_uids(
         %Brando.Blueprint.Villain.Blocks.ContainerBlock{data: %{blocks: blocks}} = block
       ) do
    updated_blocks = Enum.map(blocks, &replace_uids/1)

    block
    |> put_in([Access.key(:uid)], Brando.Utils.generate_uid())
    |> put_in([Access.key(:data), Access.key(:blocks)], updated_blocks)
  end
end
