defmodule BrandoAdmin.Components.Form.Input.Blocks.ContainerBlock do
  use Surface.LiveComponent
  use Phoenix.HTML

  import Ecto.Changeset
  import BrandoAdmin.Components.Form.Input.Blocks.Utils

  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks
  alias BrandoAdmin.Components.Modal
  alias Brando.Villain

  prop block, :any
  prop base_form, :any
  prop index, :any
  # prop block_count, :integer

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data uid, :string
  data class, :string
  data blocks, :list
  data block_forms, :list
  data block_data, :form
  data block_count, :integer
  data insert_index, :integer

  def v(form, field), do: get_field(form.source, field)

  def mount(socket) do
    {:ok, assign(socket, block_count: 0, insert_index: 0)}
  end

  def update(%{block: block} = assigns, socket) do
    block_data =
      block
      |> inputs_for(:data)
      |> List.first()

    blocks = v(block_data, :blocks)
    block_forms = inputs_for_blocks(block_data, :blocks)

    block_count = Enum.count(blocks || [])

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:uid, v(block, :uid))
     |> assign(:class, v(block_data, :class))
     |> assign(:blocks, blocks || [])
     |> assign(:block_forms, block_forms || [])
     |> assign(:block_data, block_data)
     |> assign(:block_count, block_count)}
  end

  def render(assigns) do
    ~F"""
    <div
      id={"#{@uid}-wrapper"}
      class="container-block"
      data-block-index={@index}
      data-block-uid={@uid}>

      <Blocks.Block
        id={"#{@uid}-base"}
        index={@index}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}>
        <:description>Container</:description>
        <:config></:config>
        {#if @class}

        {#else}
          Choose a section template here
        {/if}

        <Input.Text form={@block_data} field={:class} />
        <Input.Text form={@block_data} field={:description} />
        <Input.Text form={@block_data} field={:wrapper} />

        <Blocks.BlockRenderer
          id={"#{@block.id}-container-blocks"}
          base_form={@base_form}
          blocks={@block_forms}
          block_count={@block_count}
          insert_index={@insert_index}
          insert_block="insert_block"
          insert_section="insert_section"
          show_module_picker="show_module_picker"
          duplicate_block="duplicate_block" />
      </Blocks.Block>
    </div>
    """
  end

  def handle_event(
        "show_module_picker",
        %{"index" => index_binary},
        %{assigns: %{block: block}} = socket
      ) do
    modal_id = "#{block.id}-container-blocks-module-picker"
    Modal.show(modal_id)

    {:noreply, assign(socket, insert_index: index_binary)}
  end

  def handle_event(
        "insert_block",
        %{"index" => index_binary, "module-id" => module_id_binary},
        %{
          assigns: %{
            base_form: form,
            uid: block_uid,
            block: %{id: block_id}
          }
        } = socket
      ) do
    modal_id = "#{block_id}-container-blocks-module-picker"

    changeset = form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__.singular}_form"
    module_id = String.to_integer(module_id_binary)

    {:ok, modules} = Villain.list_modules(%{cache: {:ttl, :infinite}})
    module = Enum.find(modules, &(&1.id == module_id))

    # build a module block from module

    generated_uid = Brando.Utils.generate_uid() |> IO.inspect(label: "generated UID")

    {_, refs_with_generated_uids} =
      get_and_update_in(
        module.refs,
        [Access.all(), Access.key(:data), Access.key(:uid)],
        &{&1, Brando.Utils.generate_uid()}
      )

    new_block = %Brando.Blueprint.Villain.Blocks.ModuleBlock{
      type: "module",
      data: %Brando.Blueprint.Villain.Blocks.ModuleBlock.Data{
        module_id: module_id,
        multi: module.multi,
        vars: module.vars,
        refs: refs_with_generated_uids
      },
      uid: generated_uid
    }

    # TODO -- deep search? inside sections, etc
    data = get_field(changeset, :data)
    source_position = Enum.find_index(data, &(&1.uid == block_uid))
    original_block = Enum.at(data, source_position)
    sub_blocks = original_block.data.blocks || []

    # TODO: use dynamic data field
    {index, ""} = Integer.parse(index_binary)
    new_blocks = List.insert_at(sub_blocks, index, new_block)
    updated_block = put_in(original_block, [Access.key(:data), Access.key(:blocks)], new_blocks)

    # switch out container block
    # TODO: deep search?
    # TODO: use dynamic data field here

    new_data = put_in(data, [Access.filter(&match?(%{uid: ^block_uid}, &1))], updated_block)

    updated_changeset = put_change(changeset, :data, new_data)

    require Logger
    Logger.error("updated_changeset")
    Logger.error(inspect(updated_changeset.changes, pretty: true))

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    Modal.hide(modal_id)
    selector = "[data-block-uid=\"#{new_block.uid}\"]"

    {:noreply, push_event(socket, "b:scroll_to", %{selector: selector})}
  end
end
