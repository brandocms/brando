defmodule BrandoAdmin.Components.Form.Block.Events do
  use Gettext, backend: Brando.Gettext
  import Phoenix.LiveView, only: [attach_hook: 4, push_event: 3, send_update: 2]
  import Phoenix.Component
  alias Ecto.Changeset
  alias Brando.Content.TableRow
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.BlockField.ModulePicker

  def attach_block_events(socket) do
    attach_hook(socket, :block_events, :handle_event, &handle_block_event/3)
  end

  ##
  ## Block events
  def handle_block_event("duplicate_block", _, socket) do
    changeset = socket.assigns.form.source
    changesets = socket.assigns.changesets
    has_children? = socket.assigns.has_children?
    uid = socket.assigns.uid
    parent_cid = socket.assigns.parent_cid
    id = socket.assigns.id

    children =
      if has_children? do
        prefix = "#{id}-child"
        Enum.map(changesets, fn {block_uid, _} -> {"#{prefix}-#{block_uid}", block_uid} end)
      end

    send_update(parent_cid, %{
      event: "duplicate_block",
      changeset: changeset,
      children: children,
      uid: uid
    })

    {:halt, socket}
  end

  def handle_block_event("show_datasource_instructions", _, socket) do
    message =
      gettext("""
      <p>
        This block has a datasource, meaning it can load and display data from the database. There are two types:
      </p>

      <ul>
        <li><strong>List Type</strong>: Automatically lists entries based on a preset filter.</li>
        <li><strong>Selection Type</strong>: Allows you to manually select specific entries to display.</li>
      </ul>

      <p>
        Use these options to dynamically show content or highlight particular items.
      </p>
      """)

    alert_params = %{
      title: gettext("Block datasource"),
      message: message,
      type: "info"
    }

    socket
    |> push_event("b:alert", alert_params)
    |> then(&{:halt, &1})
  end

  def handle_block_event("show_vars_instructions", _, socket) do
    message =
      gettext("""
      <p>
        This block has variables, which can influence settings like size and colors,
        and allow you to add images, files, and text. Adjusting these variables
        lets you customize and manipulate the block's rendering.
      </p>
      """)

    alert_params = %{
      title: gettext("Block variables"),
      message: message,
      type: "info"
    }

    socket
    |> push_event("b:alert", alert_params)
    |> then(&{:halt, &1})
  end

  def handle_block_event("show_table_instructions", _, socket) do
    message =
      gettext("""
      <p>
        This block allows you to input tabular data following a table row template.
        The data entered here will be uniformly structured and used by the block's
        template when rendering content.
      </p>
      """)

    alert_params = %{
      title: gettext("Tabular data"),
      message: message,
      type: "info"
    }

    socket
    |> push_event("b:alert", alert_params)
    |> then(&{:halt, &1})
  end

  def handle_block_event("add_table_row", _, socket) do
    uid = socket.assigns.uid
    belongs_to = socket.assigns.belongs_to
    table_template = socket.assigns.table_template
    vars_without_pk = Brando.Villain.remove_pk_from_vars(table_template.vars)

    var_changesets =
      Enum.map(
        vars_without_pk,
        &(&1 |> Changeset.change(%{table_template_id: nil}) |> Map.put(:action, :insert))
      )

    new_row = %TableRow{vars: var_changesets}
    changeset = socket.assigns.form.source

    block_changeset =
      if belongs_to == :root, do: Changeset.get_assoc(changeset, :block), else: changeset

    current_rows = Changeset.get_assoc(block_changeset, :table_rows) || []
    new_rows = current_rows ++ List.wrap(new_row)
    updated_block_changeset = Changeset.put_assoc(block_changeset, :table_rows, new_rows)

    updated_form =
      if belongs_to == :root do
        updated_changeset = Changeset.put_assoc(changeset, :block, updated_block_changeset)

        to_form(
          updated_changeset,
          as: "entry_block",
          id: "entry_block_form-#{uid}"
        )
      else
        to_form(
          updated_block_changeset,
          as: "child_block",
          id: "child_block_form-#{uid}"
        )
      end

    socket
    |> assign(:form, updated_form)
    |> assign(:has_table_rows?, true)
    |> then(&{:halt, &1})
  end

  ## Identifier events
  def handle_block_event("assign_available_identifiers", _, socket) do
    {:halt, Block.assign_available_identifiers(socket)}
  end

  def handle_block_event("select_identifier", %{"id" => identifier_id}, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    uid = socket.assigns.uid

    block_changeset = Block.get_block_changeset(changeset, belongs_to)
    block_identifiers = Changeset.get_assoc(block_changeset, :block_identifiers)

    # check if the identifier is already assigned and if it is, remove it
    # also filter out any :replace actions
    # https://elixirforum.com/t/ecto-put-change-not-working-on-nested-changeset-when-updating/32681/2
    updated_block_identifiers =
      block_identifiers
      |> Enum.find(&(Changeset.get_field(&1, :identifier_id) == identifier_id))
      |> case do
        nil ->
          Block.insert_identifier(block_identifiers, identifier_id)

        %{action: :replace} = replaced_changeset ->
          Enum.map(block_identifiers, fn block_identifier ->
            if Changeset.get_field(block_identifier, :identifier_id) == identifier_id do
              action = (Changeset.get_field(block_identifier, :id) == nil && :insert) || nil
              Map.put(replaced_changeset, :action, action)
            else
              block_identifier
            end
          end)

        _ ->
          Block.remove_identifier(block_identifiers, identifier_id)
      end
      |> Enum.filter(&(&1.action != :replace))

    updated_block_changeset =
      Changeset.put_assoc(
        block_changeset,
        :block_identifiers,
        updated_block_identifiers
      )

    updated_changeset =
      Block.update_block_changeset(
        changeset,
        updated_block_changeset,
        belongs_to
      )

    new_form =
      if belongs_to == :root do
        to_form(updated_changeset,
          as: "entry_block",
          id: "entry_block_form-#{uid}"
        )
      else
        to_form(updated_changeset,
          as: "child_block",
          id: "child_block_form-#{uid}"
        )
      end

    socket
    |> assign(:form, new_form)
    |> Block.send_form_to_parent_stream()
    |> Block.render_module()
    |> Block.maybe_update_live_preview_block()
    |> then(&{:halt, &1})
  end

  ## Block events
  def handle_block_event("collapse_block", _, socket) do
    {:halt, assign(socket, :collapsed, !socket.assigns.collapsed)}
  end

  # fetch all module refs and add any that are missing to the block
  def handle_block_event("fetch_missing_refs", _, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    module_id = socket.assigns.module_id
    uid = Changeset.get_field(changeset, :uid)
    module = Block.get_module(module_id)

    module_refs = module.refs
    module_ref_names = Enum.map(module_refs, & &1.name)

    current_refs =
      if belongs_to == :root do
        changeset
        |> Changeset.get_assoc(:block)
        |> Changeset.get_embed(:refs)
      else
        Changeset.get_embed(changeset, :refs)
      end

    current_ref_names = Enum.map(current_refs, &Changeset.get_field(&1, :name))
    missing_ref_names = module_ref_names -- current_ref_names

    missing_refs =
      module_refs
      |> Enum.filter(&(&1.name in missing_ref_names))
      |> Enum.map(&Changeset.change/1)
      |> Brando.Villain.add_uid_to_ref_changesets()

    new_refs = current_refs ++ missing_refs

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_embed(block_changeset, :refs, new_refs)
        Changeset.put_assoc(changeset, :block, updated_block_changeset)
      else
        Changeset.put_embed(changeset, :refs, new_refs)
      end

    new_form =
      Block.build_form_from_changeset(
        updated_changeset,
        uid,
        belongs_to
      )

    socket
    |> assign(:form, new_form)
    |> then(&{:halt, &1})
  end

  # reset a single ref
  def handle_block_event("reset_ref", %{"id" => ref_name}, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    module_id = socket.assigns.module_id
    uid = Changeset.get_field(changeset, :uid)
    module = Block.get_module(module_id)

    module_refs = module.refs

    prepared_ref =
      module_refs
      |> Enum.filter(&(&1.name == ref_name))
      |> Enum.map(&Changeset.change/1)
      |> Brando.Villain.add_uid_to_ref_changesets()
      |> List.first()

    current_refs =
      if belongs_to == :root do
        changeset
        |> Changeset.get_assoc(:block)
        |> Changeset.get_embed(:refs)
      else
        Changeset.get_embed(changeset, :refs)
      end

    prepared_refs =
      current_refs
      |> Enum.reject(&(&1.action == :replace))
      |> Enum.map(fn ref ->
        if Changeset.get_field(ref, :name) == ref_name do
          prepared_ref
        else
          ref
        end
      end)

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_embed(block_changeset, :refs, prepared_refs)
        Changeset.put_assoc(changeset, :block, updated_block_changeset)
      else
        Changeset.put_embed(changeset, :refs, prepared_refs)
      end

    new_form =
      Block.build_form_from_changeset(
        updated_changeset,
        uid,
        belongs_to
      )

    socket
    |> assign(:form, new_form)
    |> then(&{:halt, &1})
  end

  def handle_block_event("reset_refs", _, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    module_id = socket.assigns.module_id
    uid = Changeset.get_field(changeset, :uid)
    module = Block.get_module(module_id)

    module_refs = module.refs

    prepared_refs =
      module_refs
      |> Enum.map(&Changeset.change/1)
      |> Brando.Villain.add_uid_to_ref_changesets()

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_embed(block_changeset, :refs, prepared_refs)
        Changeset.put_assoc(changeset, :block, updated_block_changeset)
      else
        Changeset.put_embed(changeset, :refs, prepared_refs)
      end

    new_form =
      Block.build_form_from_changeset(
        updated_changeset,
        uid,
        belongs_to
      )

    socket
    |> assign(:form, new_form)
    |> then(&{:halt, &1})
  end

  # fetch all module vars and add any that are missing to the block
  def handle_block_event("fetch_missing_vars", _, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    module_id = socket.assigns.module_id
    uid = Changeset.get_field(changeset, :uid)
    module = Block.get_module(module_id)

    module_vars = module.vars
    module_var_names = Enum.map(module_vars, & &1.key)

    current_vars =
      if belongs_to == :root do
        changeset
        |> Changeset.get_assoc(:block)
        |> Changeset.get_assoc(:vars)
      else
        Changeset.get_assoc(changeset, :vars)
      end

    current_var_names = Enum.map(current_vars, &Changeset.get_field(&1, :key))
    missing_var_names = module_var_names -- current_var_names

    missing_vars =
      module_vars
      |> Enum.filter(&(&1.key in missing_var_names))
      |> Enum.map(&Changeset.change/1)
      |> Brando.Villain.remove_pk_from_vars()

    new_vars = current_vars ++ missing_vars

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_assoc(block_changeset, :vars, new_vars)
        Changeset.put_assoc(changeset, :block, updated_block_changeset)
      else
        Changeset.put_assoc(changeset, :vars, new_vars)
      end

    new_form =
      Block.build_form_from_changeset(
        updated_changeset,
        uid,
        belongs_to
      )

    socket
    |> assign(:form, new_form)
    |> then(&{:halt, &1})
  end

  # reset all vars to module defaults
  def handle_block_event("reset_vars", _, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    module_id = socket.assigns.module_id
    uid = Changeset.get_field(changeset, :uid)
    module = Block.get_module(module_id)

    module_vars = module.vars

    original_vars =
      module_vars
      |> Enum.map(&Changeset.change/1)
      |> Brando.Villain.remove_pk_from_vars()

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_assoc(block_changeset, :vars, original_vars)
        Changeset.put_assoc(changeset, :block, updated_block_changeset)
      else
        Changeset.put_assoc(changeset, :vars, original_vars)
      end

    new_form =
      Block.build_form_from_changeset(
        updated_changeset,
        uid,
        belongs_to
      )

    socket
    |> assign(:form, new_form)
    |> then(&{:halt, &1})
  end

  # reset single var to module defaults
  def handle_block_event("reset_var", %{"id" => var_key}, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    module_id = socket.assigns.module_id
    uid = Changeset.get_field(changeset, :uid)
    module = Block.get_module(module_id)

    module_vars = module.vars

    var_to_replace =
      module_vars
      |> Enum.filter(&(&1.key == var_key))
      |> Enum.map(&Changeset.change/1)
      |> Brando.Villain.remove_pk_from_vars()
      |> List.first()

    current_vars =
      if belongs_to == :root do
        changeset
        |> Changeset.get_assoc(:block)
        |> Changeset.get_assoc(:vars)
      else
        Changeset.get_assoc(changeset, :vars)
      end

    updated_vars =
      Enum.map(current_vars, fn var ->
        if Changeset.get_field(var, :key) == var_key do
          var_to_replace
        else
          var
        end
      end)

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_assoc(block_changeset, :vars, updated_vars)
        Changeset.put_assoc(changeset, :block, updated_block_changeset)
      else
        Changeset.put_assoc(changeset, :vars, updated_vars)
      end

    new_form =
      Block.build_form_from_changeset(
        updated_changeset,
        uid,
        belongs_to
      )

    socket
    |> assign(:form, new_form)
    |> then(&{:halt, &1})
  end

  # delete single var from module
  def handle_block_event("delete_var", %{"id" => var_key}, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    uid = Changeset.get_field(changeset, :uid)

    current_vars =
      if belongs_to == :root do
        changeset
        |> Changeset.get_assoc(:block)
        |> Changeset.get_assoc(:vars)
      else
        Changeset.get_assoc(changeset, :vars)
      end

    updated_vars =
      current_vars
      |> Enum.reduce([], fn var, acc ->
        if Changeset.get_field(var, :key) == var_key do
          acc
        else
          [var | acc]
        end
      end)
      |> Enum.reverse()

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_assoc(block_changeset, :vars, updated_vars)
        Changeset.put_assoc(changeset, :block, updated_block_changeset)
      else
        Changeset.put_assoc(changeset, :vars, updated_vars)
      end

    new_form =
      Block.build_form_from_changeset(
        updated_changeset,
        uid,
        belongs_to
      )

    socket
    |> assign(:form, new_form)
    |> then(&{:halt, &1})
  end

  def handle_block_event("insert_block", value, socket) do
    # message block picker —— special case for empty container.
    block_picker_id = "block-field-#{socket.assigns.block_field}-module-picker"
    block_count = socket.assigns.block_count
    module_set = socket.assigns.module_set

    {parent_cid, sequence} =
      (Map.get(value, "container") && {socket.assigns.myself, block_count}) ||
        {socket.assigns.parent_cid, socket.assigns.form[:sequence].value}

    send_update(ModulePicker,
      id: block_picker_id,
      event: :show_module_picker,
      filter: %{parent_id: nil, namespace: module_set},
      module_set: module_set,
      type: :module,
      sequence: sequence,
      parent_cid: parent_cid
    )

    {:halt, socket}
  end

  def handle_block_event("insert_block_entry", value, socket) do
    block_picker_id = "block-field-#{socket.assigns.block_field}-module-picker"
    parent_cid = (Map.get(value, "multi") && socket.assigns.myself) || socket.assigns.parent_cid
    block_count = socket.assigns.block_count
    sequence = (Map.get(value, "multi") && block_count) || socket.assigns.form[:sequence].value

    module_id =
      if socket.assigns.parent_module_id do
        socket.assigns.parent_module_id
      else
        socket.assigns.module_id
      end

    send_update(ModulePicker,
      id: block_picker_id,
      event: :show_module_picker,
      filter: %{parent_id: module_id, namespace: "all"},
      module_set: "all",
      type: :module_entry,
      sequence: sequence,
      parent_cid: parent_cid
    )

    {:halt, socket}
  end

  # reposition a main block
  def handle_block_event(
        "reposition",
        %{"id" => _id, "new" => new_idx, "old" => old_idx, "parent_uid" => _parent_uid},
        socket
      )
      when new_idx == old_idx do
    {:halt, socket}
  end

  def handle_block_event(
        "reposition",
        %{"uid" => uid, "new" => new_idx, "old" => old_idx, "parent_uid" => _parent_uid},
        socket
      ) do
    block_list = socket.assigns.block_list
    changesets = socket.assigns.changesets

    new_block_list =
      block_list
      |> List.delete_at(old_idx)
      |> List.insert_at(new_idx, uid)

    # we must reposition the children changesets list according to the new block_list
    new_changesets =
      Enum.map(new_block_list, fn block_uid ->
        Enum.find(changesets, fn
          {^block_uid, _} -> true
          _ -> false
        end)
      end)

    socket
    |> assign(:block_list, new_block_list)
    |> assign(:changesets, new_changesets)
    |> Block.reset_position_response_tracker()
    |> Block.send_child_position_update(new_block_list)
    |> then(&{:halt, &1})
  end

  def handle_block_event("show_dirty", _params, socket) do
    require Logger

    Logger.debug("""

    changeset.changes
    #{inspect(socket.assigns.form.source.changes)}

    """)

    {:halt, socket}
  end

  def handle_block_event("delete_block", _params, socket) do
    uid = socket.assigns.uid
    parent_cid = socket.assigns.parent_cid
    dom_id = socket.assigns.dom_id

    send_update(parent_cid, %{
      event: "delete_block",
      uid: uid,
      dom_id: dom_id
    })

    {:halt, assign(socket, :deleted, true)}
  end

  def handle_block_event("focus", %{"field" => field_name}, socket) do
    current_user_id = socket.assigns.current_user_id
    entry = socket.assigns.entry

    Phoenix.PubSub.broadcast(
      Brando.pubsub(),
      "brando:active_field:#{entry.id}",
      {:active_field, field_name, current_user_id}
    )

    {:halt, socket}
  end

  def handle_block_event("validate_block", %{"_target" => params_target, "child_block" => params}, socket) do
    form = socket.assigns.form
    changeset = form.source
    uid = socket.assigns.uid
    current_user_id = socket.assigns.current_user_id
    entry = socket.assigns.entry
    has_vars? = socket.assigns.has_vars?
    has_table_rows? = socket.assigns.has_table_rows?

    updated_changeset =
      changeset.data
      |> Brando.Content.Block.block_changeset(params, current_user_id)
      |> Map.put(:action, :validate)
      |> Block.render_and_update_block_changeset(entry, has_vars?, has_table_rows?)

    updated_form =
      to_form(updated_changeset,
        as: "child_block",
        id: "child_block_form-#{uid}"
      )

    socket
    |> assign(:form, updated_form)
    |> assign(:form_has_changes, updated_form.source.changes !== %{})
    |> Block.send_form_to_parent_stream()
    |> Block.maybe_update_liquex_block_var(params_target, params)
    |> Block.maybe_update_live_preview_block()
    |> then(&{:halt, &1})
  end

  def handle_block_event("validate_block", %{"_target" => params_target, "entry_block" => params}, socket) do
    form = socket.assigns.form
    changeset = form.source
    uid = socket.assigns.uid
    block_module = socket.assigns.block_module
    current_user_id = socket.assigns.current_user_id
    entry = socket.assigns.entry
    has_vars? = socket.assigns.has_vars?
    has_children? = socket.assigns.has_children?
    has_table_rows? = socket.assigns.has_table_rows?

    # Use apply_changes to get struct with our in-memory modifications (like image_id updates)
    # instead of changeset.data which reverts to original database values
    updated_changeset =
      changeset
      |> Changeset.apply_changes()
      |> block_module.changeset(params, current_user_id)
      |> Map.put(:action, :validate)

    # if this is a container and it's flipped from active = false to true,
    # then we must force an update to the live preview to get the rendered children.
    force_render? = Block.should_force_live_preview_update?(changeset, updated_changeset, :root)

    updated_changeset =
      updated_changeset
      |> Block.render_and_update_entry_block_changeset(
        entry,
        has_vars?,
        has_table_rows?,
        force_render?
      )
      |> Block.maybe_put_empty_children(has_children?)

    updated_form =
      to_form(updated_changeset,
        as: "entry_block",
        id: "entry_block_form-#{uid}"
      )

    socket
    |> assign(:form, updated_form)
    |> assign(:form_has_changes, updated_form.source.changes !== %{})
    |> Block.maybe_update_liquex_block_var(params_target, params)
    |> Block.maybe_update_container(params_target)
    |> Block.maybe_update_fragment(params_target)
    |> Block.maybe_update_live_preview_block()
    |> Block.send_form_to_parent_stream()
    |> then(&{:halt, &1})
  end

  # Fallback for any unhandled events
  def handle_block_event(event, params, socket) do
    IO.puts("Unhandled event in events.ex: #{event} with params #{inspect(params)}")
    {:cont, socket}
  end
end
