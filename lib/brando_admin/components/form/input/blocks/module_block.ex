# # TODO: Delete after moving all events to `Block` / `BlockField`
# defmodule BrandoAdmin.Components.Form.Input.Blocks.ModuleBlock do
#   import Brando.Gettext
#   import BrandoAdmin.Components.Form.Input.Blocks.Utils

#   alias Brando.Villain
#   alias BrandoAdmin.Components.Content
#   alias BrandoAdmin.Components.Form
#   alias BrandoAdmin.Components.Form.Input
#   alias BrandoAdmin.Components.Form.Input.Entries
#   alias BrandoAdmin.Components.Form.Input.RenderVar
#   alias BrandoAdmin.Components.Form.Input.Blocks

#   # def handle_event(
#   #       "fetch_missing_vars",
#   #       _,
#   #       %{
#   #         assigns: %{
#   #           base_form: base_form,
#   #           uid: block_uid,
#   #           block_data: block_data,
#   #           data_field: data_field,
#   #           module_id: module_id
#   #         }
#   #       } = socket
#   #     ) do
#   #   {:ok, module} = Brando.Content.get_module(module_id)

#   #   changeset = base_form.source

#   #   current_vars = block_data[:vars].value || []
#   #   current_var_keys = Enum.map(current_vars, & &1.key)

#   #   module_vars = module.vars || []
#   #   module_var_keys = Enum.map(module_vars, & &1.key)

#   #   missing_var_keys = module_var_keys -- current_var_keys
#   #   missing_vars = Enum.filter(module_vars, &(&1.key in missing_var_keys))

#   #   new_vars = current_vars ++ missing_vars

#   #   updated_changeset =
#   #     Villain.update_block_in_changeset(
#   #       changeset,
#   #       data_field,
#   #       block_uid,
#   #       %{data: %{vars: new_vars}}
#   #     )

#   #   schema = changeset.data.__struct__
#   #   form_id = "#{schema.__naming__().singular}_form"

#   #   send_update(BrandoAdmin.Components.Form,
#   #     id: form_id,
#   #     action: :update_changeset,
#   #     changeset: updated_changeset
#   #   )

#   #   {:noreply, assign(socket, :important_vars, Enum.filter(new_vars, &(&1.important == true)))}
#   # end

#   # def handle_event(
#   #       "reset_vars",
#   #       _,
#   #       %{
#   #         assigns: %{
#   #           base_form: base_form,
#   #           uid: block_uid,
#   #           data_field: data_field,
#   #           module_id: module_id
#   #         }
#   #       } = socket
#   #     ) do
#   #   {:ok, module} = Brando.Content.get_module(module_id)

#   #   changeset = base_form.source

#   #   updated_changeset =
#   #     Villain.update_block_in_changeset(
#   #       changeset,
#   #       data_field,
#   #       block_uid,
#   #       %{data: %{vars: module.vars || []}}
#   #     )

#   #   schema = changeset.data.__struct__
#   #   form_id = "#{schema.__naming__().singular}_form"

#   #   send_update(BrandoAdmin.Components.Form,
#   #     id: form_id,
#   #     action: :update_changeset,
#   #     changeset: updated_changeset
#   #   )

#   #   {:noreply,
#   #    assign(socket, :important_vars, Enum.filter(module.vars || [], &(&1.important == true)))}
#   # end

#   # def handle_event(
#   #       "reset_var",
#   #       %{"id" => var_id},
#   #       %{
#   #         assigns: %{
#   #           base_form: base_form,
#   #           uid: block_uid,
#   #           block_data: block_data,
#   #           data_field: data_field,
#   #           module_id: module_id
#   #         }
#   #       } = socket
#   #     ) do
#   #   {:ok, module} = Brando.Content.get_module(module_id)

#   #   changeset = base_form.source

#   #   reset_var = Enum.find(module.vars, &(&1.key == var_id))
#   #   current_vars = block_data[:vars].value

#   #   updated_vars =
#   #     Enum.map(current_vars, fn
#   #       %{key: ^var_id} -> reset_var
#   #       var -> var
#   #     end)

#   #   updated_changeset =
#   #     Villain.update_block_in_changeset(
#   #       changeset,
#   #       data_field,
#   #       block_uid,
#   #       %{data: %{vars: updated_vars}}
#   #     )

#   #   schema = changeset.data.__struct__
#   #   form_id = "#{schema.__naming__().singular}_form"

#   #   send_update(BrandoAdmin.Components.Form,
#   #     id: form_id,
#   #     action: :update_changeset,
#   #     changeset: updated_changeset
#   #   )

#   #   {:noreply, socket}
#   # end

#   # def handle_event(
#   #       "delete_var",
#   #       %{"id" => var_id},
#   #       %{
#   #         assigns: %{
#   #           base_form: base_form,
#   #           uid: block_uid,
#   #           block_data: block_data,
#   #           data_field: data_field
#   #         }
#   #       } = socket
#   #     ) do
#   #   changeset = base_form.source
#   #   updated_vars = Enum.reject(block_data[:vars].value, &(&1.key == var_id))

#   #   updated_changeset =
#   #     Villain.update_block_in_changeset(
#   #       changeset,
#   #       data_field,
#   #       block_uid,
#   #       %{data: %{vars: updated_vars}}
#   #     )

#   #   schema = changeset.data.__struct__
#   #   form_id = "#{schema.__naming__().singular}_form"

#   #   send_update(BrandoAdmin.Components.Form,
#   #     id: form_id,
#   #     action: :update_changeset,
#   #     changeset: updated_changeset
#   #   )

#   #   {:noreply, socket}
#   # end

#   # def handle_event(
#   #       "fetch_missing_refs",
#   #       _,
#   #       %{
#   #         assigns: %{
#   #           base_form: base_form,
#   #           uid: block_uid,
#   #           block_data: block_data,
#   #           data_field: data_field,
#   #           module_id: module_id
#   #         }
#   #       } = socket
#   #     ) do
#   #   {:ok, module} = Brando.Content.get_module(module_id)

#   #   changeset = base_form.source

#   #   current_refs = block_data[:refs].value
#   #   current_ref_names = Enum.map(current_refs, & &1.name)

#   #   module_refs = module.refs
#   #   module_ref_names = Enum.map(module_refs, & &1.name)

#   #   missing_ref_names = module_ref_names -- current_ref_names
#   #   missing_refs = Enum.filter(module_refs, &(&1.name in missing_ref_names))

#   #   new_refs = current_refs ++ missing_refs

#   #   refs_with_generated_uids = Brando.Villain.add_uid_to_refs(new_refs)

#   #   updated_changeset =
#   #     Villain.update_block_in_changeset(
#   #       changeset,
#   #       data_field,
#   #       block_uid,
#   #       %{data: %{refs: refs_with_generated_uids}}
#   #     )

#   #   schema = changeset.data.__struct__
#   #   form_id = "#{schema.__naming__().singular}_form"

#   #   send_update(BrandoAdmin.Components.Form,
#   #     id: form_id,
#   #     action: :update_changeset,
#   #     changeset: updated_changeset
#   #   )

#   #   {:noreply, socket}
#   # end

#   # def handle_event(
#   #       "reset_refs",
#   #       _,
#   #       %{
#   #         assigns: %{
#   #           base_form: base_form,
#   #           uid: block_uid,
#   #           data_field: data_field,
#   #           module_id: module_id
#   #         }
#   #       } = socket
#   #     ) do
#   #   {:ok, module} = Brando.Content.get_module(module_id)

#   #   changeset = base_form.source

#   #   refs_with_generated_uids = Brando.Villain.add_uid_to_refs(module.refs)

#   #   updated_changeset =
#   #     Villain.update_block_in_changeset(
#   #       changeset,
#   #       data_field,
#   #       block_uid,
#   #       %{data: %{refs: refs_with_generated_uids}}
#   #     )

#   #   schema = changeset.data.__struct__
#   #   form_id = "#{schema.__naming__().singular}_form"

#   #   send_update(BrandoAdmin.Components.Form,
#   #     id: form_id,
#   #     action: :update_changeset,
#   #     changeset: updated_changeset
#   #   )

#   #   {:noreply, socket}
#   # end

#   # def handle_event(
#   #       "reset_ref",
#   #       %{"id" => ref_id},
#   #       %{
#   #         assigns: %{
#   #           base_form: base_form,
#   #           uid: block_uid,
#   #           block_data: block_data,
#   #           data_field: data_field,
#   #           module_id: module_id
#   #         }
#   #       } = socket
#   #     ) do
#   #   {:ok, module} = Brando.Content.get_module(module_id)

#   #   changeset = base_form.source

#   #   reset_ref = Enum.find(module.refs, &(&1.name == ref_id))
#   #   current_refs = block_data[:refs].value

#   #   updated_refs =
#   #     Enum.map(current_refs, fn
#   #       %{name: ^ref_id} -> reset_ref
#   #       ref -> ref
#   #     end)

#   #   updated_refs_with_generated_uids = Brando.Villain.add_uid_to_refs(updated_refs)

#   #   updated_changeset =
#   #     Villain.update_block_in_changeset(
#   #       changeset,
#   #       data_field,
#   #       block_uid,
#   #       %{data: %{refs: updated_refs_with_generated_uids}}
#   #     )

#   #   schema = changeset.data.__struct__
#   #   form_id = "#{schema.__naming__().singular}_form"

#   #   send_update(BrandoAdmin.Components.Form,
#   #     id: form_id,
#   #     action: :update_changeset,
#   #     changeset: updated_changeset
#   #   )

#   #   {:noreply, socket}
#   # end
# end
