defmodule BrandoAdmin.Components.Form.BlockField.Outline do
  @moduledoc """
  Outline/minimap drawer for the block builder.

  Shows a condensed tree view of all blocks with drag-and-drop
  reordering and click-to-scroll navigation.
  """
  use BrandoAdmin, :component
  use Gettext, backend: Brando.Gettext

  alias BrandoAdmin.Components.Content

  attr :id, :string, required: true
  attr :outline_items, :list, required: true
  attr :block_field, :atom, required: true
  attr :target, :any, required: true

  def outline_drawer(assigns) do
    ~H"""
    <Content.drawer
      id={@id}
      title={gettext("Outline")}
      close={toggle_drawer("##{@id}")}
      narrow
      light
      left
    >
      <div class="outline-tree">
        <%= if @outline_items == [] do %>
          <p class="outline-empty">{gettext("No blocks yet")}</p>
        <% else %>
          <.outline_root_list
            outline_items={@outline_items}
            block_field={@block_field}
            target={@target}
          />
        <% end %>
      </div>
    </Content.drawer>
    """
  end

  attr :outline_items, :list, required: true
  attr :block_field, :atom, required: true
  attr :target, :any, required: true

  defp outline_root_list(assigns) do
    ~H"""
    <div
      id={"outline-root-#{@block_field}"}
      phx-hook="Brando.SortableBlocks"
      data-sortable-id={"sortable-outline-root-#{@block_field}"}
      data-sortable-handle=".outline-item-row"
      data-sortable-selector=".outline-item"
      data-drop="outline_root_reposition"
    >
      <.outline_item
        :for={item <- @outline_items}
        :key={item.uid}
        item={item}
        target={@target}
      />
    </div>
    """
  end

  attr :item, :map, required: true
  attr :target, :any, required: true

  defp outline_item(assigns) do
    ~H"""
    <div
      id={"outline-#{@item.uid}"}
      class={["outline-item", !@item.active && "inactive"]}
      data-uid={@item.uid}
    >
      <div
        class="outline-item-row"
        phx-click={Phoenix.LiveView.JS.push("outline_scroll_to", target: @target, value: %{uid: @item.uid})}
      >
        <span class={["color-dot", "color-#{@item.module_color}"]}></span>
        <div class="outline-item-label">
          <span class="type-label">{type_label(@item.type, @item.multi)}</span>
          <span :if={@item.module_name} class="module-name">
            <.i18n map={@item.module_name} />
          </span>
          <span :if={@item.description not in ["", nil]} class="description">
            {@item.description}
          </span>
        </div>
      </div>
      <%= if @item.children != [] do %>
        <.outline_children item={@item} target={@target} />
      <% end %>
    </div>
    """
  end

  attr :item, :map, required: true
  attr :target, :any, required: true

  defp outline_children(assigns) do
    group_name = children_group_name(assigns.item)
    assigns = assign(assigns, :group_name, group_name)

    ~H"""
    <div
      id={"outline-children-#{@item.uid}"}
      class="outline-children"
      phx-hook="Brando.SortableBlocks"
      data-sortable-id={"sortable-outline-children-#{@item.uid}"}
      data-sortable-handle=".outline-item-row"
      data-sortable-selector=".outline-item"
      data-blocks-wrapper-type={@group_name}
      data-parent-uid={@item.uid}
      data-drop="outline_reposition"
    >
      <.outline_item
        :for={child <- @item.children}
        :key={child.uid}
        item={child}
        target={@target}
      />
    </div>
    """
  end

  defp children_group_name(%{type: :container}), do: "outline-container-children"
  defp children_group_name(%{type: :module, multi: true, module_id: mid}), do: "outline-multi-#{mid}"
  defp children_group_name(_), do: nil

  defp type_label(:module, true), do: gettext("Multi")
  defp type_label(:module, _), do: gettext("Module")
  defp type_label(:module_entry, _), do: gettext("Entry")
  defp type_label(:container, _), do: gettext("Container")
  defp type_label(:fragment, _), do: gettext("Fragment")
  defp type_label(_, _), do: ""

  @doc """
  Builds a single outline item map from a `%Brando.Content.Block{}` struct.

  Recursively processes children blocks. BlockField materializes each root
  from the op store and applies it before calling this — the outline always
  reflects live structure, not mount-time seeds.
  """
  def build_outline_item_from_struct(%Brando.Content.Block{} = block) do
    {module_name, module_color, multi} =
      resolve_module(block.module_id, Map.get(block, :module_origin, :local))

    children =
      case block.children do
        %Ecto.Association.NotLoaded{} -> []
        nil -> []
        list -> Enum.map(list, &build_outline_item_from_struct/1)
      end

    %{
      uid: block.uid,
      type: block.type,
      module_id: block.module_id,
      module_name: module_name,
      module_color: module_color,
      description: block.description,
      active: block.active,
      multi: multi,
      children: children
    }
  end

  defp resolve_module(nil, _origin), do: {nil, :blue, false}

  defp resolve_module(module_id, origin) do
    case Brando.Content.fetch_module(module_id, origin) do
      nil -> {nil, :blue, false}
      module -> {module.name, module.color || :blue, module.multi || false}
    end
  end
end
