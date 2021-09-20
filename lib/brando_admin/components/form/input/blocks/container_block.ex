defmodule BrandoAdmin.Components.Form.Input.Blocks.ContainerBlock do
  use Surface.LiveComponent
  use Phoenix.HTML

  import Ecto.Changeset
  import BrandoAdmin.Components.Form.Input.Blocks.Utils

  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks
  alias BrandoAdmin.Components.Modal

  alias Brando.Content

  prop block, :any
  prop base_form, :any
  prop index, :any
  prop uploads, :any
  prop data_field, :atom
  prop belongs_to, :string

  prop insert_block, :event, required: true
  prop duplicate_block, :event, required: true

  data uid, :string
  data blocks, :list
  data block_forms, :list
  data block_data, :form
  data block_count, :integer
  data insert_index, :integer

  data selected_section, :map
  data available_sections, :list
  data section_options, :list

  def v(form, field), do: input_value(form, field)

  def mount(socket) do
    {:ok,
     socket
     |> assign(insert_index: 0)}
  end

  def assign_available_sections(socket) do
    socket
    |> assign_new(:available_sections, fn ->
      {:ok, available_sections} = Content.list_sections(%{cache: {:ttl, :infinite}})
      available_sections
    end)
  end

  def assign_section_options(%{assigns: %{available_sections: available_sections}} = socket) do
    assign_new(socket, :section_options, fn ->
      Enum.map(
        available_sections,
        &%{
          label:
            ~s(<span class="circle small" style="margin-right: 12px;background-color:#{&1.color_bg}"></span> #{&1.name}),
          value: &1.id
        }
      )
    end)
  end

  def get_section(nil), do: nil

  def get_section(section_id, available_sections) do
    Enum.find(available_sections, &(&1.id == section_id))
  end

  def assign_selected_section(
        %{assigns: %{available_sections: available_sections, block_data: block_data}} = socket
      ) do
    assign(
      socket,
      :selected_section,
      get_section(v(block_data, :section_id), available_sections)
    )
  end

  def update(%{block: block} = assigns, socket) do
    require Logger
    Logger.error(inspect("==> updating container_block!"))

    block_data =
      block
      |> inputs_for(:data)
      |> List.first()

    blocks = v(block_data, :blocks)
    block_forms = inputs_for_blocks(block_data, :blocks) || []

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:uid, v(block, :uid))
     |> assign(:blocks, blocks || [])
     |> assign(:block_forms, block_forms)
     |> assign(:block_data, block_data)
     |> assign_available_sections()
     |> assign_section_options()
     |> assign_selected_section()}
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
        belongs_to={@belongs_to}
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}
        bg_color={@selected_section && "#{@selected_section.color_bg}22"}>
        <:description>
          {#if @selected_section}
            <span class="circle tiny" style={"background-color:#{@selected_section.color_bg}"}></span> {@selected_section.name}
          {#else}
            No section selected
          {/if}
        </:description>
        <:config>
          {#if @selected_section}
            Select a new section<br>
            <Input.Select
              id={"#{@block_data.id}-section-select"}
              form={@block_data}
              field={:section_id}
              options={@section_options}
            />
          {/if}
        </:config>
        {#if !@selected_section}
          <Input.Select
            id={"#{@block_data.id}-section-select"}
            form={@block_data}
            field={:section_id}
            options={@section_options}
          />
        {/if}

        <Blocks.BlockRenderer
          id={"#{@block.id}-container-blocks"}
          base_form={@base_form}
          blocks={@blocks}
          block_forms={@block_forms}
          data_field={@data_field}
          uploads={@uploads}
          type="container"
          uid={@uid}
          hide_sections
          insert_index={@insert_index}
          insert_block="insert_block"
          insert_section="insert_section"
          insert_datasource="insert_datasource"
          show_module_picker="show_module_picker"
          duplicate_block="duplicate_block"
        />
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
            block: %{id: block_id},
            data_field: data_field
          }
        } = socket
      ) do
    modal_id = "#{block_id}-container-blocks-module-picker"

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

    # TODO -- Villain.update_block_in_changeset
    data = get_field(changeset, data_field)
    source_position = Enum.find_index(data, &(&1.uid == block_uid))
    original_block = Enum.at(data, source_position)
    sub_blocks = original_block.data.blocks || []

    {index, ""} = Integer.parse(index_binary)
    new_blocks = List.insert_at(sub_blocks, index, new_block)
    updated_block = put_in(original_block, [Access.key(:data), Access.key(:blocks)], new_blocks)

    # switch out container block

    new_data = put_in(data, [Access.filter(&match?(%{uid: ^block_uid}, &1))], updated_block)
    updated_changeset = put_change(changeset, data_field, new_data)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    Modal.hide(modal_id)
    selector = "[data-block-uid=\"#{new_block.uid}\"]"

    {:noreply, push_event(socket, "b:scroll_to", %{selector: selector})}
  end
end
