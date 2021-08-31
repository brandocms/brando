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

  def update(%{input: %{name: name, opts: opts}} = assigns, socket) do
    blocks = inputs_for_blocks(assigns.form, name)
    {:ok, modules} = Villain.list_modules(%{cache: {:ttl, :infinite}})
    block_count = Enum.count(blocks)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:modules_by_namespace, fn ->
       modules
       |> Brando.Utils.split_by(:namespace)
       |> Enum.map(&__MODULE__.sort_namespace/1)
     end)
     |> assign(:blocks, blocks)
     |> assign(:block_count, block_count)}
  end

  def sort_namespace({namespace, modules}) do
    sorted_modules = Enum.sort(modules, &(&1.sequence <= &2.sequence))
    {namespace, sorted_modules}
  end

  def render(%{input: %{name: name}} = assigns) do
    ~F"""
    <FieldBase
      blueprint={@blueprint}
      form={@form}
      field={name}>

      <div class="blocks-wrapper">
        <Modal title="Add content block" id={"#{@form.id}-#{name}-module-picker"} medium>
          <div class="button-group-horizontal">
            <button type="button" class="builtin-button">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="24" height="24"><path fill="none" d="M0 0h24v24H0z"/><path d="M3 3h18a1 1 0 0 1 1 1v16a1 1 0 0 1-1 1H3a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1zm17 8H4v8h16v-8zm0-2V5H4v4h16zM9 6h2v2H9V6zM5 6h2v2H5V6z"/></svg>
              Insert section
            </button>
            <button type="button" class="builtin-button">
              <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="128"><path fill="none" d="M0 0h24v24H0z"/><path d="M5 12.5c0 .313.461.858 1.53 1.393C7.914 14.585 9.877 15 12 15c2.123 0 4.086-.415 5.47-1.107 1.069-.535 1.53-1.08 1.53-1.393v-2.171C17.35 11.349 14.827 12 12 12s-5.35-.652-7-1.671V12.5zm14 2.829C17.35 16.349 14.827 17 12 17s-5.35-.652-7-1.671V17.5c0 .313.461.858 1.53 1.393C7.914 19.585 9.877 20 12 20c2.123 0 4.086-.415 5.47-1.107 1.069-.535 1.53-1.08 1.53-1.393v-2.171zM3 17.5v-10C3 5.015 7.03 3 12 3s9 2.015 9 4.5v10c0 2.485-4.03 4.5-9 4.5s-9-2.015-9-4.5zm9-7.5c2.123 0 4.086-.415 5.47-1.107C18.539 8.358 19 7.813 19 7.5c0-.313-.461-.858-1.53-1.393C16.086 5.415 14.123 5 12 5c-2.123 0-4.086.415-5.47 1.107C5.461 6.642 5 7.187 5 7.5c0 .313.461.858 1.53 1.393C7.914 9.585 9.877 10 12 10z"/></svg>
              Insert datasource
            </button>
          </div>

          <div
            class="modules"
            phx-hook="Brando.ModulePicker"
            id={"#{@form.id}-#{name}-module-picker-modules"}>
            {#for {namespace, modules} <- @modules_by_namespace}
              {#unless namespace == "general"}
                <button type="button" class="namespace-button">
                  <figure>
                    &rarr;
                  </figure>
                  <div class="info">
                    <div class="name">{namespace}</div>
                    <div class="instructions">{Enum.count(modules)} modules</div>
                  </div>
                </button>
                <div class="namespace-modules">
                  {#for module <- modules}
                    <button
                      type="button"
                      class="module-button"
                      :on-click="insert_block"
                      phx-value-index={@insert_index}
                      phx-value-module-id={module.id}>
                      <figure>
                        {module.svg |> raw}
                      </figure>
                      <div class="info">
                        <div class="name">{module.name}</div>
                        <div class="instructions">{module.help_text}</div>
                      </div>
                    </button>
                  {/for}
                </div>
              {/unless}
            {/for}
            {#for {namespace, modules} <- @modules_by_namespace}
              {#if namespace == "general"}
                {#for module <- modules}
                  <button
                    type="button"
                    class="module-button"
                    :on-click="insert_block"
                    phx-value-index={@insert_index}
                    phx-value-module-id={module.id}>
                    <figure>
                      {module.svg |> raw}
                    </figure>
                    <div class="info">
                      <div class="name">{module.name}</div>
                      <div class="instructions">{module.help_text}</div>
                    </div>
                  </button>
                {/for}
              {/if}
            {/for}
          </div>
        </Modal>

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
            block_count={@block_count}
            block={block_form}
            base_form={@form}
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
