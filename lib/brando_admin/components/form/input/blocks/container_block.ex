defmodule BrandoAdmin.Components.Form.Input.Blocks.ContainerBlock do
  use BrandoAdmin, :live_component
  use Phoenix.HTML
  import BrandoAdmin.Components.Form.Input.Blocks.Utils

  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks
  alias Brando.Content

  # prop block, :any
  # prop base_form, :any
  # prop index, :any
  # prop uploads, :any
  # prop data_field, :atom
  # prop belongs_to, :string

  # prop insert_block, :event, required: true
  # prop duplicate_block, :event, required: true

  # data uid, :string
  # data blocks, :list
  # data block_forms, :list
  # data block_data, :form
  # data block_count, :integer
  # data insert_index, :integer

  # data selected_palette, :map
  # data available_palettes, :list
  # data palette_options, :list
  # data first_color, :string

  def v(form, field), do: input_value(form, field)

  def mount(socket) do
    {:ok,
     socket
     |> assign(insert_index: 0)}
  end

  def assign_available_palettes(socket) do
    socket
    |> assign_new(:available_palettes, fn ->
      {:ok, available_palettes} = Content.list_palettes(%{cache: {:ttl, :infinite}})
      available_palettes
    end)
  end

  def assign_palette_options(%{assigns: %{available_palettes: available_palettes}} = socket) do
    assign_new(socket, :palette_options, fn -> prepare_palettes(available_palettes) end)
  end

  def prepare_palettes(available_palettes) do
    Enum.map(available_palettes, fn palette ->
      colors =
        Enum.map(Enum.reverse(palette.colors), fn color ->
          """
          <span
            class="circle tiny"
            style="background-color:#{color.hex_value}"></span>
          """
        end)

      label = """
      <div class="circle-stack mr-1">
        #{colors}
      </div>
      - #{palette.name}
      """

      %{label: label, value: palette.id}
    end)
  end

  def get_palette(nil), do: nil

  def get_palette(palette_id, available_palettes) do
    Enum.find(available_palettes, &(&1.id == palette_id))
  end

  def assign_selected_palette(
        %{assigns: %{available_palettes: available_palettes, block_data: block_data}} = socket
      ) do
    selected_palette = get_palette(v(block_data, :palette_id), available_palettes)

    socket
    |> assign(:selected_palette, selected_palette)
    |> assign(
      :first_color,
      List.first((selected_palette && selected_palette.colors) || ["#FFFFFF"])
    )
  end

  def update(%{block: block} = assigns, socket) do
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
     |> assign_available_palettes()
     |> assign_palette_options()
     |> assign_selected_palette()}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"block-#{@uid}-wrapper"}
      class="container-block"
      data-block-index={@index}
      data-block-uid={@uid}>

      <.live_component
        module={Blocks.Block}
        id={"block-#{@uid}-base"}
        index={@index}
        block_count={@block_count}
        base_form={@base_form}
        block={@block}
        belongs_to={@belongs_to}
        insert_block={@insert_block}
        duplicate_block={@duplicate_block}
        bg_color={@selected_palette && "#{@first_color.hex_value}22"}>
        <:description>
          <%= if @selected_palette do %>
            <%= @selected_palette.name %>
            <div class="circle-stack">
              <%= for color <- Enum.reverse(@selected_palette.colors) do %>
                <span
                  class="circle tiny"
                  style={"background-color:#{color.hex_value}"}
                  data-popover={"#{color.name}"}></span>
              <% end %>
            </div>
          <% else %>
            No palette selected
          <% end %>
        </:description>
        <:config>
          <%= if @selected_palette do %>
            <div class="instructions mb-1">Select a new palette:</div>
            <.live_component
              module={Input.Select}
              id={"#{@block_data.id}-palette-select"}
              form={@block_data}
              field={:palette_id}
              opts={[options: @palette_options]}
            />
          <% end %>
        </:config>
        <%= if !@selected_palette do %>
          <.live_component
            module={Input.Select}
            id={"#{@block_data.id}-palette-select"}
            form={@block_data}
            field={:palette_id}
            opts={[options: @palette_options]}
          />
        <% end %>

        <.live_component
          module={Blocks.BlockRenderer}
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
          insert_block={JS.push("insert_block", target: @myself)|> hide_modal("##{@block.id}-container-blocks-module-picker")}
          insert_section={JS.push("insert_section", target: @myself)|> hide_modal("##{@block.id}-container-blocks-module-picker")}
          insert_datasource={JS.push("insert_datasource", target: @myself)|> hide_modal("##{@block.id}-container-blocks-module-picker")}
          show_module_picker={JS.push("show_module_picker", target: @myself) |> show_modal("##{@block.id}-container-blocks-module-picker")}
          duplicate_block={JS.push("duplicate_block", target: @myself)}
        />
      </.live_component>
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
        "insert_block",
        %{"index" => index_binary, "module-id" => module_id_binary},
        %{
          assigns: %{
            base_form: form,
            uid: block_uid,
            data_field: data_field
          }
        } = socket
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

    original_block = Brando.Villain.get_block_in_changeset(changeset, data_field, block_uid)
    sub_blocks = original_block.data.blocks || []
    {index, ""} = Integer.parse(index_binary)
    new_blocks = List.insert_at(sub_blocks, index, new_block)

    updated_changeset =
      Brando.Villain.update_block_in_changeset(changeset, data_field, block_uid, %{
        data: %{blocks: new_blocks}
      })

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
        %{
          assigns: %{
            base_form: form,
            uid: block_uid,
            data_field: data_field
          }
        } = socket
      ) do
    changeset = form.source
    module = changeset.data.__struct__
    form_id = "#{module.__naming__().singular}_form"

    new_block = %Brando.Blueprint.Villain.Blocks.DatasourceBlock{
      type: "datasource",
      data: %Brando.Blueprint.Villain.Blocks.DatasourceBlock.Data{},
      uid: Brando.Utils.generate_uid()
    }

    original_block = Brando.Villain.get_block_in_changeset(changeset, data_field, block_uid)
    sub_blocks = original_block.data.blocks || []
    {index, ""} = Integer.parse(index_binary)
    new_blocks = List.insert_at(sub_blocks, index, new_block)

    updated_changeset =
      Brando.Villain.update_block_in_changeset(changeset, data_field, block_uid, %{
        data: %{blocks: new_blocks}
      })

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      updated_changeset: updated_changeset
    )

    selector = "[data-block-uid=\"#{new_block.uid}\"]"

    {:noreply, push_event(socket, "b:scroll_to", %{selector: selector})}
  end
end
