# # TODO: Deprecate and delete.
# defmodule BrandoAdmin.Components.Form.Input.Blocks do
#   use BrandoAdmin, :live_component
#   # use Phoenix.HTML

#   import BrandoAdmin.Components.Form.Input.Blocks.Utils
#   import Brando.Gettext
#   import Ecto.Changeset
#   import Phoenix.LiveView.TagEngine

#   alias BrandoAdmin.Components.Content
#   alias BrandoAdmin.Components.Form
#   alias BrandoAdmin.Components.Form.Input
#   alias BrandoAdmin.Components.Form.Input.Blocks

#   def mount(socket) do
#     {:ok, assign(socket, insert_index: 0)}
#   end

#   def update(%{image_drawer_target: target}, socket) do
#     {:ok, assign(socket, :image_drawer_target, target)}
#   end

#   def update(assigns, socket) do
#     blocks = assigns.field.value || []
#     block_forms = inputs_for_blocks(assigns.field) || []

#     {:ok,
#      socket
#      |> assign(assigns)
#      |> assign_new(:image_drawer_target, fn -> socket.assigns.myself end)
#      |> assign_new(:templates, fn ->
#        if template_namespace = assigns.opts[:template_namespace] do
#          {:ok, templates} =
#            Brando.Content.list_templates(%{filter: %{namespace: template_namespace}})

#          templates
#        else
#          nil
#        end
#      end)
#      |> assign(:blocks, blocks)
#      |> assign(:block_forms, block_forms)
#      |> assign(:data_field, assigns.field)}
#   end

#   def handle_event("insert_fragment", %{"index" => index_binary}, socket) do
#     field = socket.assigns.field
#     changeset = field.form.source
#     module = changeset.data.__struct__
#     form_id = "#{module.__naming__().singular}_form"

#     new_block = %Brando.Villain.Blocks.FragmentBlock{
#       type: "fragment",
#       data: %Brando.Villain.Blocks.FragmentBlock.Data{
#         fragment_id: nil
#       },
#       uid: Brando.Utils.generate_uid()
#     }

#     {index, ""} = Integer.parse(index_binary)

#     new_data =
#       changeset
#       |> get_blocks_data()
#       |> List.insert_at(index, new_block)

#     updated_changeset = put_change(changeset, :data, new_data)

#     send_update(BrandoAdmin.Components.Form,
#       id: form_id,
#       action: :update_changeset,
#       changeset: updated_changeset
#     )

#     selector = "[data-block-uid=\"#{new_block.uid}\"]"

#     {:noreply, push_event(socket, "b:scroll_to", %{selector: selector})}
#   end

#   def handle_event("duplicate_block", %{"block_uid" => block_uid}, socket) do
#     field = socket.assigns.field
#     field_name = field.field
#     changeset = field.form.source
#     data = get_field(changeset, field_name)
#     source_position = Enum.find_index(data, &(&1.uid == block_uid))

#     module = changeset.data.__struct__
#     form_id = "#{module.__naming__().singular}_form"

#     duplicated_block =
#       data
#       |> Enum.at(source_position)
#       |> replace_uids()

#     new_data = List.insert_at(data, source_position + 1, duplicated_block)

#     updated_changeset = put_change(changeset, field_name, new_data)

#     send_update(BrandoAdmin.Components.Form,
#       id: form_id,
#       action: :update_changeset,
#       changeset: updated_changeset,
#       force_validation: true
#     )

#     {:noreply, socket}
#   end
# end
