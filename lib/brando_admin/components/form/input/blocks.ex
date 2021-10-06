defmodule BrandoAdmin.Components.Form.Input.Blocks do
  use Surface.LiveComponent
  use Phoenix.HTML

  import Ecto.Changeset
  import BrandoAdmin.Components.Form.Input.Blocks.Utils

  alias Brando.Content
  alias Brando.Utils
  alias BrandoAdmin.Components.Modal
  alias BrandoAdmin.Components.Form.FieldBase
  alias BrandoAdmin.Components.Form.Input.Blocks

  prop form, :form
  prop blueprint, :any
  prop uploads, :any

  data blocks, :list
  data block_forms, :list
  data insert_index, :integer
  data data_field, :atom
  data templates, :any

  def mount(socket) do
    {:ok, assign(socket, insert_index: 0)}
  end

  def update(%{form: form, input: %{name: name, opts: opts}} = assigns, socket) do
    # TODO: when using input_value here, we sometimes end up with the whole block field as a params map %{"0" => ...}
    blocks = Utils.iv(assigns.form, name) || []
    block_forms = inputs_for_blocks(form, name) || []

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:templates, fn ->
       if template_namespace = opts[:template_namespace] do
         {:ok, templates} = Content.list_templates(%{filter: %{namespace: template_namespace}})
         templates
       else
         nil
       end
     end)
     |> assign(:blocks, blocks)
     |> assign(:block_forms, block_forms)
     |> assign(:data_field, name)}
  end

  def render(%{input: %{name: name}} = assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      form={@form}
      field={name}>

      <Blocks.BlockRenderer
        id={"#{@form.id}-#{name}-blocks"}
        base_form={@form}
        blocks={@blocks}
        block_forms={@block_forms}
        uploads={@uploads}
        templates={@templates}
        data_field={@data_field}
        insert_index={@insert_index}
        insert_block="insert_block"
        insert_section="insert_section"
        insert_datasource="insert_datasource"
        show_module_picker="show_module_picker"
        duplicate_block="duplicate_block" />

    </FieldBase>
    """
  end

  def handle_event(
        "show_module_picker",
        %{"index" => index_binary},
        %{assigns: %{form: form, input: %{name: name}}} = socket
      ) do
    modal_id = "#{form.id}-#{name}-blocks-module-picker"
    Modal.show(modal_id)

    {:noreply, assign(socket, insert_index: index_binary)}
  end

  def handle_event(
        "insert_section",
        %{"index" => index_binary},
        %{assigns: %{form: form, input: %{name: name}}} = socket
      ) do
    modal_id = "#{form.id}-#{name}-blocks-module-picker"

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

    Modal.hide(modal_id)
    selector = "[data-block-uid=\"#{new_block.uid}\"]"

    {:noreply, push_event(socket, "b:scroll_to", %{selector: selector})}
  end

  def handle_event(
        "insert_datasource",
        %{"index" => index_binary},
        %{assigns: %{form: form, input: %{name: name}}} = socket
      ) do
    modal_id = "#{form.id}-#{name}-blocks-module-picker"

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

    Modal.hide(modal_id)
    selector = "[data-block-uid=\"#{new_block.uid}\"]"

    {:noreply, push_event(socket, "b:scroll_to", %{selector: selector})}
  end

  def handle_event(
        "insert_block",
        %{"index" => index_binary, "module-id" => module_id_binary},
        %{assigns: %{form: form, input: %{name: name}}} = socket
      ) do
    modal_id = "#{form.id}-#{name}-blocks-module-picker"

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

    Modal.hide(modal_id)
    selector = "[data-block-uid=\"#{new_block.uid}\"]"

    {:noreply, push_event(socket, "b:scroll_to", %{selector: selector})}
  end

  def handle_event(
        "duplicate_block",
        %{"block_uid" => block_uid},
        %{assigns: %{form: form, input: %{name: data_field}}} = socket
      ) do
    changeset = form.source
    data = get_field(changeset, data_field)
    source_position = Enum.find_index(data, &(&1.uid == block_uid))

    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    duplicated_block =
      data
      |> Enum.at(source_position)
      |> Map.put(:uid, Brando.Utils.random_string(13) |> String.upcase())

    new_data = List.insert_at(data, source_position + 1, duplicated_block)
    updated_changeset = put_change(changeset, data_field, new_data)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    {:noreply, socket}
  end

  defp get_blocks_data(changeset) do
    get_field(changeset, :data) || []
  end
end
