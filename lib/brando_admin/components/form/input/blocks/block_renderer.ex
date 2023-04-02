defmodule BrandoAdmin.Components.Form.Input.Blocks.BlockRenderer do
  use BrandoAdmin, :live_component
  use Phoenix.HTML
  import Brando.Gettext

  alias BrandoAdmin.Components.Form.Input.Blocks

  # prop blocks, :list, required: true
  # prop block_forms, :list, required: true
  # prop base_form, :form, required: true
  # prop data_field, :atom, required: true
  # prop insert_index, :integer
  # prop insert_module, :event, required: true
  # prop insert_section, :event, required: true
  # prop duplicate_block, :event, required: true
  # prop show_module_picker, :event, required: true
  # prop parent_uploads, :any
  # prop templates, :any
  # prop type, :string, default: "root"
  # prop uid, :string

  @doc "If sections should be visible in the module picker"
  # prop hide_sections, :boolean
  # prop hide_fragments, :boolean

  # data block_count, :integer

  def update(assigns, socket) do
    # TODO: Only count on initial render, then trigger a count from
    # "insert_module", "delete_block", "duplicate_block", "insert_section", "insert_datasource" etc?

    block_count =
      assigns.block_forms
      |> Enum.map(& &1[:marked_as_deleted].value)
      |> Enum.reject(&(&1 == true))
      |> Enum.count()

    {:ok,
     socket
     |> assign(assigns)
     |> assign_new(:opts, fn -> [] end)
     |> assign_new(:templates, fn -> [] end)
     |> assign_new(:type, fn -> "root" end)
     |> assign_new(:hide_sections, fn -> false end)
     |> assign_new(:hide_fragments, fn -> false end)
     |> assign(:block_count, block_count)
     |> assign(:indexed_block_forms, Enum.with_index(assigns.block_forms))}
  end

  def render(assigns) do
    ~H"""
    <div
      id={"#{@id}-blocks-wrapper"}
      class="blocks-wrapper"
      phx-hook="Brando.SortableBlocks"
      data-blocks-wrapper-type={@type}>

      <.live_component module={Blocks.ModulePicker}
        id={"#{@id}-module-picker"}
        insert_module={@insert_module}
        insert_section={@insert_section}
        insert_fragment={@insert_fragment}
        insert_index={@insert_index}
        hide_sections={@hide_sections}
        hide_fragments={@hide_fragments} />

      <%= if @block_count == 0 do %>
        <div class="blocks-empty-instructions">
          <%= gettext "Click the plus to start adding content blocks" %>
          <%= if @templates && @templates != [] do %>
            <br><%= gettext "or get started with a prefab'ed template" %>:<br>
            <div class="blocks-templates">
              <%= for template <- @templates do %>
                <button type="button" phx-click={JS.push("use_template", target: @myself)} phx-value-id={template.id}>
                  <%= template.name %><br>
                  <small><%= template.instructions %></small>
                </button>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>

      <%= for {block_form, index} <- @indexed_block_forms do %>
        <Blocks.dynamic_block
          parent_uploads={@parent_uploads}
          index={index}
          data_field={@data_field}
          base_form={@base_form}
          block_count={@block_count}
          block={block_form}
          belongs_to={@type}
          opts={@opts}
          insert_module={@show_module_picker}
          duplicate_block={@duplicate_block} />
      <% end %>

      <Blocks.Plus.render
        index={@block_count}
        click={@show_module_picker} />
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
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: true
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
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: true
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
      action: :update_changeset,
      changeset: updated_changeset,
      force_validation: true
    )

    {:noreply, socket}
  end
end
