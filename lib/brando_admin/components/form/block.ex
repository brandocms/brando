defmodule BrandoAdmin.Components.Form.Block do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext
  alias Ecto.Changeset
  alias BrandoAdmin.Components.Form.BlockField
  alias BrandoAdmin.Components.Form.Block.Events
  alias Brando.Content.Blocks, as: ContentBlocks

  def mount(socket) do
    socket
    |> assign(:block_initialized, false)
    |> assign(:container_not_found, false)
    |> assign(:module_not_found, false)
    |> assign(:entry_template, nil)
    |> assign(:initial_render, false)
    |> assign(:dom_id, nil)
    |> assign(:children_forms, [])
    |> assign(:position_response_tracker, [])
    |> assign(:source, nil)
    |> assign(:live_preview_active?, false)
    |> assign(:live_preview_cache_key, nil)
    |> assign_new(:clipboard_meta, fn -> nil end)
    |> Events.attach_block_events()
    |> then(&{:ok, &1})
  end

  # fetch_for_shipping — collect current changeset and send to BlockField for broadcasting
  # set_collapsed — explicitly set the collapsed state (used by bulk collapse/expand)
  def update(%{event: "set_collapsed", collapsed: collapsed}, socket) do
    changeset = socket.assigns.form.source
    uid = socket.assigns.uid
    belongs_to = socket.assigns.belongs_to

    updated_changeset =
      if belongs_to == :root do
        block_cs = Changeset.get_assoc(changeset, :block)
        updated_block_cs = Changeset.put_change(block_cs, :collapsed, collapsed)
        Changeset.put_assoc(changeset, :block, updated_block_cs)
      else
        Changeset.put_change(changeset, :collapsed, collapsed)
      end

    new_form = build_form_from_changeset(updated_changeset, uid, belongs_to)

    socket
    |> assign(:form, new_form)
    |> assign(:collapsed, collapsed)
    |> then(&{:ok, &1})
  end

  # set_children_collapsed — forward collapse state to all children of a multi/container block
  def update(%{event: "set_children_collapsed", collapsed: collapsed}, socket) do
    parent_id = socket.assigns.id
    block_list = socket.assigns.block_list

    for block_uid <- block_list do
      send_update(__MODULE__,
        id: "#{parent_id}-child-#{block_uid}",
        event: "set_collapsed",
        collapsed: collapsed
      )
    end

    {:ok, socket}
  end

  def update(%{event: "fetch_for_shipping"}, socket) do
    changeset = socket.assigns.form.source

    send_to_ref(socket.assigns.parent_ref, %{
      event: "ship_block_data",
      uid: socket.assigns.uid,
      changeset: changeset
    })

    {:ok, socket}
  end

  # copy_block — intermediate blocks forward copy requests up the parent chain to BlockField
  def update(%{event: "copy_block"} = msg, socket) do
    send_to_ref(socket.assigns.parent_ref, msg)
    {:ok, socket}
  end

  # paste_block — child block requests paste; forward up to BlockField
  def update(%{event: "paste_block", sequence: sequence}, socket) do
    send_to_ref(socket.assigns.parent_ref, %{
      event: "paste_child_block",
      parent_ref: {__MODULE__, socket.assigns.id},
      sequence: sequence
    })

    {:ok, socket}
  end

  # paste_child_block — already has parent_ref, forward preserving it
  def update(%{event: "paste_child_block", parent_ref: _} = msg, socket) do
    send_to_ref(socket.assigns.parent_ref, msg)
    {:ok, socket}
  end

  # paste_child_block — no parent_ref, add myself
  def update(%{event: "paste_child_block", sequence: sequence}, socket) do
    send_to_ref(socket.assigns.parent_ref, %{
      event: "paste_child_block",
      parent_ref: {__MODULE__, socket.assigns.id},
      sequence: sequence
    })

    {:ok, socket}
  end

  # insert_pasted_block — BlockField sends pasted block changeset to be inserted as child
  def update(%{event: "insert_pasted_block", block_cs: block_cs, sequence: sequence}, socket) do
    uid = Changeset.get_field(block_cs, :uid)
    block_list = socket.assigns.block_list
    new_block_list = List.insert_at(block_list, sequence, uid)

    block_form = to_form(block_cs, as: "child_block", id: "child_block_form-#{uid}")
    changesets = socket.assigns.changesets
    updated_changesets = insert_child_changeset(changesets, uid, sequence)
    selector = "[data-block-uid=\"#{uid}\"]"

    socket
    |> update(:children_forms, &List.insert_at(&1, sequence, block_form))
    |> assign(:has_children?, true)
    |> assign(:block_list, new_block_list)
    |> assign(:changesets, updated_changesets)
    |> update(:block_count, &(&1 + 1))
    |> reset_position_response_tracker()
    |> send_child_position_update(new_block_list)
    |> push_event("b:scroll_to", %{selector: selector})
    |> then(&{:ok, &1})
  end

  # Outline: reorder a child within this parent
  def update(%{event: "outline_reorder_child", child_uid: uid, old: old_idx, new: new_idx}, socket) do
    block_list = socket.assigns.block_list
    changesets = socket.assigns.changesets

    new_block_list =
      block_list
      |> List.delete_at(old_idx)
      |> List.insert_at(new_idx, uid)

    new_changesets =
      Enum.map(new_block_list, fn block_uid ->
        Enum.find(changesets, fn
          {^block_uid, _} -> true
          _ -> false
        end)
      end)

    new_forms =
      Enum.map(new_block_list, fn block_uid ->
        Enum.find(socket.assigns.children_forms, fn form ->
          Changeset.get_field(form.source, :uid) == block_uid
        end)
      end)

    socket
    |> assign(:children_forms, new_forms)
    |> assign(:block_list, new_block_list)
    |> assign(:changesets, new_changesets)
    |> reset_position_response_tracker()
    |> send_child_position_update(new_block_list)
    |> then(&{:ok, &1})
  end

  # Outline: extract a child for cross-parent move
  def update(
        %{event: "extract_child", child_uid: uid, target_parent_uid: target_uid, target_sequence: seq},
        socket
      ) do
    block_list = socket.assigns.block_list
    changesets = socket.assigns.changesets
    children_forms = socket.assigns.children_forms

    # Get the child changeset from the form (changesets list may have nil values)
    child_changeset =
      Enum.find_value(children_forms, fn form ->
        if Changeset.get_field(form.source, :uid) == uid, do: form.source
      end)

    # Remove from lists
    new_block_list = List.delete(block_list, uid)

    new_changesets =
      Enum.reject(changesets, fn
        {^uid, _} -> true
        _ -> false
      end)

    new_forms =
      Enum.reject(children_forms, fn form ->
        Changeset.get_field(form.source, :uid) == uid
      end)

    has_children? = new_block_list !== []

    # Send the child to BlockField for relay to target parent
    send_to_ref(socket.assigns.parent_ref, %{
      event: "insert_extracted_child",
      target_parent_uid: target_uid,
      child_changeset: child_changeset,
      sequence: seq
    })

    socket
    |> assign(:block_list, new_block_list)
    |> assign(:changesets, new_changesets)
    |> assign(:children_forms, new_forms)
    |> assign(:has_children?, has_children?)
    |> assign(:block_count, length(new_block_list))
    |> reset_position_response_tracker()
    |> send_child_position_update(new_block_list)
    |> then(&{:ok, &1})
  end

  # duplicate block (that is not an entry block)
  # event is received in the parent block (multi or container)
  # this is received when the block is done gathering all its children changesets
  def update(%{event: "duplicate_block", uid: uid, changeset: block_cs, populated: true}, socket) do
    block_list = socket.assigns.block_list
    changesets = socket.assigns.changesets
    sequence = Enum.find_index(block_list, &(&1 == uid))
    new_sequence = sequence + 1
    current_user_id = socket.assigns.current_user_id
    new_uid = Brando.Utils.generate_uid()

    updated_block_cs =
      ContentBlocks.duplicate_block(block_cs, user_id: current_user_id, sequence: new_sequence, uid: new_uid)

    # insert the new block uid into the block_list
    new_block_list = List.insert_at(block_list, new_sequence, new_uid)

    block_form =
      to_form(updated_block_cs,
        as: "child_block",
        id: "child_block_form-#{new_uid}"
      )

    updated_changesets = insert_child_changeset(changesets, new_uid, new_sequence)
    selector = "[data-block-uid=\"#{new_uid}\"]"

    socket
    |> update(:children_forms, &List.insert_at(&1, new_sequence, block_form))
    |> assign(:has_children?, true)
    |> assign(:block_list, new_block_list)
    |> assign(:changesets, updated_changesets)
    |> update(:block_count, &(&1 + 1))
    |> reset_position_response_tracker()
    |> send_child_position_update(new_block_list)
    |> push_event("b:scroll_to", %{selector: selector})
    |> reset_changesets(uid)
    |> then(&{:ok, &1})
  end

  def update(%{event: "duplicate_block", uid: uid, changeset: block_cs, children: children}, socket) do
    block_list = socket.assigns.block_list
    changesets = socket.assigns.changesets
    sequence = Enum.find_index(block_list, &(&1 == uid))
    new_sequence = sequence + 1
    current_user_id = socket.assigns.current_user_id
    new_uid = Brando.Utils.generate_uid()

    if children do
      # the block we wish to duplicate has children so we need to message
      # them to gather their changesets. We will do the duplication once we
      # have received all changesets.
      for {id, block_uid} <- children do
        send_update(__MODULE__,
          id: id,
          event: "fetch_changeset_for_duplication",
          uid: block_uid,
          parent_uid: uid,
          root_uid: uid,
          parent_sequence: sequence,
          action: :duplicate
        )
      end

      {:ok, socket}
    else
      updated_block_cs =
        ContentBlocks.duplicate_block(block_cs, user_id: current_user_id, sequence: new_sequence, uid: new_uid)

      # insert the new block uid into the block_list
      new_block_list = List.insert_at(block_list, sequence, new_uid)

      block_form =
        to_form(updated_block_cs,
          as: "child_block",
          id: "child_block_form-#{new_uid}"
        )

      updated_changesets = insert_child_changeset(changesets, new_uid, sequence)
      selector = "[data-block-uid=\"#{new_uid}\"]"

      socket
      |> update(:children_forms, &List.insert_at(&1, sequence, block_form))
      |> assign(:has_children?, true)
      |> assign(:block_list, new_block_list)
      |> assign(:changesets, updated_changesets)
      |> update(:block_count, &(&1 + 1))
      |> reset_position_response_tracker()
      |> send_child_position_update(new_block_list)
      |> push_event("b:scroll_to", %{selector: selector})
      |> then(&{:ok, &1})
    end
  end

  def update(
        %{
          event: "fetch_changeset_for_duplication",
          uid: uid,
          parent_uid: parent_uid,
          root_uid: root_uid,
          parent_sequence: parent_sequence
        } = msg,
        socket
      ) do
    action = Map.get(msg, :action, :duplicate)
    changeset = socket.assigns.form.source
    has_children? = socket.assigns.has_children?
    parent_ref = socket.assigns.parent_ref

    if has_children? do
      changesets = socket.assigns.changesets
      id = socket.assigns.id

      for {block_uid, _} <- changesets do
        id = "#{id}-child-#{block_uid}"

        send_update(__MODULE__,
          id: id,
          event: "fetch_changeset_for_duplication",
          uid: block_uid,
          parent_uid: uid,
          root_uid: root_uid,
          parent_sequence: parent_sequence,
          action: action
        )
      end

      {:ok, socket}
    else
      send_to_ref(parent_ref, %{
        event: "provide_changeset_for_duplication",
        changeset: changeset,
        uid: uid,
        parent_uid: parent_uid,
        root_uid: root_uid,
        parent_sequence: parent_sequence,
        action: action
      })

      {:ok, socket}
    end
  end

  def update(
        %{
          event: "provide_changeset_for_duplication",
          uid: uid,
          changeset: child_changeset,
          root_uid: root_uid,
          parent_uid: parent_uid,
          parent_sequence: parent_sequence
        } = msg,
        socket
      ) do
    action = Map.get(msg, :action, :duplicate)
    changeset = socket.assigns.form.source
    changesets = socket.assigns.changesets
    updated_changesets = update_child_changeset(changesets, uid, child_changeset)
    this_uid = socket.assigns.uid
    parent_ref = socket.assigns.parent_ref

    if !Enum.any?(updated_changesets, &(elem(&1, 1) == nil)) do
      updated_changesets_list = Enum.map(updated_changesets, &elem(&1, 1))

      updated_changeset = put_children(changeset, updated_changesets_list)

      if root_uid == this_uid do
        # Terminal: send populated changeset to parent for duplication or copy
        event_name = if action == :copy, do: "copy_block", else: "duplicate_block"

        send_to_ref(parent_ref, %{
          event: event_name,
          uid: root_uid,
          changeset: updated_changeset,
          populated: true
        })
      else
        send_to_ref(parent_ref, %{
          event: "provide_changeset_for_duplication",
          changeset: updated_changeset,
          uid: this_uid,
          parent_uid: parent_uid,
          root_uid: root_uid,
          parent_sequence: parent_sequence,
          action: action
        })
      end
    end

    {:ok, assign(socket, :changesets, updated_changesets)}
  end

  # event sent from RenderVar for :file, :image, :link vars
  def update(%{event: "update_block_var"} = params, socket) do
    %{var_key: var_key, var_type: var_type, data: data} = params

    socket
    |> update_changeset_data_block_var(var_key, var_type, data)
    |> update_liquex_block_var(var_key, var_type, data)
    |> then(&{:ok, &1})
  end

  def update(%{event: "enable_live_preview", cache_key: cache_key}, socket) do
    has_children? = socket.assigns.has_children?
    changesets = socket.assigns.changesets
    id = socket.assigns.id

    if has_children? do
      Enum.each(changesets, fn {block_uid, _} ->
        child_id = "#{id}-child-#{block_uid}"

        send_update(__MODULE__,
          id: child_id,
          event: "enable_live_preview",
          cache_key: cache_key
        )
      end)
    end

    socket
    |> assign(:live_preview_active?, true)
    |> assign(:live_preview_cache_key, cache_key)
    |> maybe_render_module()
    |> then(&{:ok, &1})
  end

  def update(%{event: "disable_live_preview"}, socket) do
    has_children? = socket.assigns.has_children?
    changesets = socket.assigns.changesets
    id = socket.assigns.id

    if has_children? do
      Enum.each(changesets, fn {block_uid, _} ->
        child_id = "#{id}-child-#{block_uid}"

        send_update(__MODULE__,
          id: child_id,
          event: "disable_live_preview"
        )
      end)
    end

    socket
    |> assign(:live_preview_active?, false)
    |> assign(:live_preview_cache_key, nil)
    |> then(&{:ok, &1})
  end

  def update(%{event: "delete_block", uid: uid, dom_id: _dom_id}, socket) do
    changesets = socket.assigns.changesets
    block_list = socket.assigns.block_list
    updated_changesets = delete_child_changeset(changesets, uid)
    new_block_list = List.delete(block_list, uid)
    changeset = socket.assigns.form.source
    belongs_to = socket.assigns.belongs_to
    block_cs = get_block_changeset(changeset, belongs_to)

    has_children? = new_block_list !== []

    # if we deleted the last child block, put_assoc the empty children list
    updated_block_cs =
      if has_children? do
        block_cs
      else
        Changeset.put_assoc(block_cs, :children, [])
      end

    updated_form =
      if belongs_to == :root do
        updated_changeset = Changeset.put_assoc(changeset, :block, updated_block_cs)

        to_form(
          updated_changeset,
          as: "entry_block",
          id: "entry_block_form-#{uid}"
        )
      else
        to_form(
          updated_block_cs,
          as: "child_block",
          id: "child_block_form-#{uid}"
        )
      end

    socket
    |> assign(:changesets, updated_changesets)
    |> assign(:block_list, new_block_list)
    |> assign(:has_children?, has_children?)
    |> assign(:form, updated_form)
    |> update(:children_forms, fn forms ->
      Enum.reject(forms, &(Changeset.get_field(&1.source, :uid) == uid))
    end)
    |> update(:block_count, &(&1 - 1))
    |> reset_position_response_tracker()
    |> send_child_position_update(new_block_list)
    |> update_live_preview_on_empty_block_list()
    |> then(&{:ok, &1})
  end

  def update(%{event: "update_sequence", sequence: sequence}, socket) do
    belongs_to = socket.assigns.belongs_to
    parent_ref = socket.assigns.parent_ref
    changeset = socket.assigns.form.source
    uid = socket.assigns.uid

    updated_block_cs =
      changeset
      |> get_block_changeset(belongs_to)
      |> Changeset.put_change(:sequence, sequence)

    updated_form =
      if belongs_to == :root do
        updated_changeset =
          changeset
          |> Changeset.put_assoc(:block, updated_block_cs)
          |> Changeset.put_change(:sequence, sequence)

        to_form(
          updated_changeset,
          as: "entry_block",
          id: "entry_block_form-#{uid}"
        )
      else
        to_form(
          updated_block_cs,
          as: "child_block",
          id: "child_block_form-#{uid}"
        )
      end

    send_to_ref(parent_ref, %{event: "signal_position_update", uid: uid})

    {:ok,
     socket
     |> assign(:form_has_changes, updated_form.source.changes !== %{})
     |> assign(:form, updated_form)}
  end

  def update(%{event: "signal_position_update", uid: uid}, socket) do
    BrandoAdmin.Components.Form.BlockChangesetList.handle_position_response(socket, uid)
  end

  def update(%{event: "clear_changesets"}, socket) do
    id = socket.assigns.id
    has_children? = socket.assigns.has_children?

    if has_children? do
      changesets = socket.assigns.changesets
      cleared_changesets = Enum.map(changesets, &{elem(&1, 0), nil})

      for {block_uid, _} <- changesets do
        id = "#{id}-child-#{block_uid}"

        send_update(__MODULE__,
          id: id,
          event: "clear_changesets"
        )
      end

      {:ok, assign(socket, :changesets, cleared_changesets)}
    else
      {:ok, socket}
    end
  end

  def update(%{event: "fetch_root_block", tag: tag}, socket) do
    # a message we will receive from the block field
    id = socket.assigns.id
    parent_ref = socket.assigns.parent_ref
    changeset = socket.assigns.form.source
    uid = socket.assigns.uid
    has_children? = socket.assigns.has_children?
    changesets = socket.assigns.changesets

    if socket.assigns.deleted do
      # if the block is deleted, we don't message the children.
      if tag == :save do
        send(self(), {:progress_popup, "Providing block #{uid}..."})
      end

      send_to_ref(parent_ref, %{
        event: "provide_root_block",
        changeset: nil,
        uid: uid,
        tag: tag
      })
    else
      # if the block has children we message them to gather their changesets
      if has_children? do
        for {block_uid, _} <- changesets do
          id = "#{id}-child-#{block_uid}"

          send_update(__MODULE__,
            id: id,
            event: "fetch_child_block",
            uid: block_uid,
            tag: tag
          )
        end
      else
        # if the block has no children we send the current changeset back to the parent
        if tag == :save do
          send(self(), {:progress_popup, "Providing root block #{uid}..."})
        end

        send_to_ref(parent_ref, %{
          event: "provide_root_block",
          changeset: changeset,
          uid: uid,
          tag: tag
        })
      end
    end

    {:ok, socket}
  end

  def update(%{event: "fetch_child_block", tag: tag}, socket) do
    # a message we will receive from parent block
    id = socket.assigns.id
    parent_ref = socket.assigns.parent_ref
    changeset = socket.assigns.form.source
    uid = socket.assigns.uid
    has_children? = socket.assigns.has_children?
    changesets = socket.assigns.changesets

    # if the block has children we message them to gather their changesets
    if has_children? do
      for {block_uid, _} <- changesets do
        id = "#{id}-child-#{block_uid}"

        send_update(__MODULE__,
          id: id,
          event: "fetch_child_block",
          uid: block_uid,
          tag: tag
        )
      end
    else
      # if the block has no children we send the current changeset back to the parent
      if tag == :save do
        send(self(), {:progress_popup, "Providing block #{uid}..."})
      end

      send_to_ref(parent_ref, %{
        event: "provide_child_block",
        changeset: changeset,
        uid: uid,
        tag: tag
      })
    end

    {:ok, socket}
  end

  def update(%{event: "provide_child_block", changeset: child_changeset, uid: uid, tag: tag}, socket) do
    parent_uid = socket.assigns.uid
    parent_ref = socket.assigns.parent_ref
    level = socket.assigns.level
    changeset = socket.assigns.form.source

    changesets = socket.assigns.changesets
    updated_changesets = update_child_changeset(changesets, uid, child_changeset)

    if !Enum.any?(updated_changesets, &(elem(&1, 1) == nil)) do
      updated_changesets_list = Enum.map(updated_changesets, &elem(&1, 1))

      updated_changeset = put_children(changeset, updated_changesets_list)

      if level == 0 do
        if tag == :save do
          send(self(), {:progress_popup, "Providing root block #{uid}..."})
        end

        send_to_ref(parent_ref, %{
          event: "provide_root_block",
          changeset: updated_changeset,
          uid: parent_uid,
          tag: tag
        })
      else
        if tag == :save do
          send(self(), {:progress_popup, "Providing block #{uid}..."})
        end

        send_to_ref(parent_ref, %{
          event: "provide_child_block",
          changeset: updated_changeset,
          uid: parent_uid,
          tag: tag
        })
      end
    end

    {:ok, assign(socket, :changesets, updated_changesets)}
  end

  def update(%{event: "update_block", form: form}, socket) do
    uid = Changeset.get_field(form.source, :uid)

    updated =
      Enum.map(socket.assigns.children_forms, fn child_form ->
        if Changeset.get_field(child_form.source, :uid) == uid, do: form, else: child_form
      end)

    {:ok, assign(socket, :children_forms, updated)}
  end

  def update(%{event: "insert_block", sequence: sequence, module_id: module_id, type: type}, socket) do
    module_id = String.to_integer(module_id)
    user_id = socket.assigns.current_user_id
    parent_id = nil
    sequence = (is_binary(sequence) && String.to_integer(sequence)) || sequence
    source = socket.assigns.block_module

    empty_block_cs = BlockField.build_block(module_id, user_id, parent_id, source, type)
    uid = Changeset.get_field(empty_block_cs, :uid)
    # insert the new block uid into the block_list
    block_list = socket.assigns.block_list
    updated_block_list = List.insert_at(block_list, sequence, uid)

    block_form =
      to_change_form(
        empty_block_cs,
        %{sequence: sequence},
        user_id
      )

    changesets = socket.assigns.changesets
    updated_changesets = insert_child_changeset(changesets, uid, sequence)

    selector = "[data-block-uid=\"#{uid}\"]"

    socket
    |> update(:children_forms, &List.insert_at(&1, sequence, block_form))
    |> assign(:has_children?, true)
    |> assign(:block_list, updated_block_list)
    |> assign(:changesets, updated_changesets)
    |> update(:block_count, &(&1 + 1))
    |> reset_position_response_tracker()
    |> send_child_position_update(updated_block_list)
    |> push_event("b:scroll_to", %{selector: selector})
    |> then(&{:ok, &1})
  end

  def update(%{event: "update_ref", ref: ref}, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    uid = socket.assigns.uid
    has_vars? = socket.assigns.has_vars?
    has_table_rows? = socket.assigns.has_table_rows?
    entry = socket.assigns.entry

    block_changeset = get_block_changeset(changeset, belongs_to)
    refs = Ecto.Changeset.get_assoc(block_changeset, :refs)

    new_refs =
      Enum.reduce(refs, [], fn
        %Changeset{action: :replace}, acc ->
          acc

        old_ref, acc ->
          old_ref_name = Changeset.get_field(old_ref, :name)

          if old_ref_name == ref.name do
            # Update the existing changeset with new data
            updated_ref_changeset =
              old_ref
              |> Changeset.change(%{
                uid: ref.uid,
                description: ref.description || Changeset.get_field(old_ref, :description)
              })
              |> Changeset.force_change(:data, ref.data)

            acc ++ List.wrap(updated_ref_changeset)
          else
            acc ++ List.wrap(old_ref)
          end
      end)

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_assoc(block_changeset, :refs, new_refs)
        changeset = Changeset.put_assoc(changeset, :block, updated_block_changeset)
        render_and_update_entry_block_changeset(changeset, entry, has_vars?, has_table_rows?)
      else
        changeset = Changeset.put_assoc(changeset, :refs, new_refs)
        render_and_update_block_changeset(changeset, entry, has_vars?, has_table_rows?)
      end

    new_form =
      build_form_from_changeset(
        updated_changeset,
        uid,
        belongs_to
      )

    socket
    |> assign(:form, new_form)
    |> send_form_to_parent()
    |> maybe_update_live_preview_block()
    |> then(&{:ok, &1})
  end

  def update(%{event: "update_ref_data", ref_name: ref_name} = params, socket) do
    ref_data = Map.get(params, :ref_data)
    force_render? = Map.get(params, :force_render, false)
    propagate? = Map.get(params, :propagate, false)
    media_ref? = media_ref_change?(params)
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    uid = socket.assigns.uid
    has_vars? = socket.assigns.has_vars?
    has_table_rows? = socket.assigns.has_table_rows?
    entry = socket.assigns.entry

    block_changeset = get_block_changeset(changeset, belongs_to)
    refs = Changeset.get_assoc(block_changeset, :refs)

    new_refs =
      Enum.reduce(refs, [], fn
        %Changeset{action: :replace}, acc ->
          acc

        ref, acc ->
          if Changeset.get_field(ref, :name) == ref_name do
            # Update the block data (only if ref_data provided)
            block =
              ref
              |> Changeset.get_field(:data)
              |> Changeset.change()

            {updated_block, updated_ref} =
              if ref_data do
                updated_block = Changeset.put_embed(block, :data, ref_data)
                updated_ref = Changeset.force_change(ref, :data, updated_block)
                {updated_block, updated_ref}
              else
                {block, ref}
              end

            # Handle video_data if provided (creates/updates video association)
            updated_ref =
              if Map.has_key?(params, :video_data) do
                video_data = params.video_data
                current_user_id = socket.assigns.current_user_id

                case Brando.Videos.create_video(video_data, current_user_id) do
                  {:ok, video} ->
                    updated_ref
                    |> Changeset.put_change(:video_id, video.id)
                    |> Map.put(:data, Map.put(updated_ref.data, :video, nil))

                  {:error, _} ->
                    updated_ref
                end
              else
                updated_ref
              end

            # Also update media associations if provided (including nil values)
            updated_ref =
              updated_ref
              |> put_change_if_key_exists(:image_id, params)
              |> put_change_if_key_exists(:video_id, params)
              |> put_change_if_key_exists(:gallery_id, params)
              |> put_change_if_key_exists(:file_id, params)
              |> clear_preloaded_associations(params)

            # Handle adding media (image or video) to gallery association
            {updated_ref, updated_block} =
              cond do
                Map.has_key?(params, :add_gallery_image_id) ->
                  current_user = %{id: socket.assigns.current_user_id}
                  id = params.add_gallery_image_id
                  updated_ref = add_media_to_gallery_ref(updated_ref, :image, id, current_user)
                  updated_block = add_gallery_media_override(updated_block, id, :image)
                  {updated_ref, updated_block}

                Map.has_key?(params, :add_gallery_video_id) ->
                  current_user = %{id: socket.assigns.current_user_id}
                  id = params.add_gallery_video_id
                  updated_ref = add_media_to_gallery_ref(updated_ref, :video, id, current_user)
                  updated_block = add_gallery_media_override(updated_block, id, :video)
                  {updated_ref, updated_block}

                true ->
                  {updated_ref, updated_block}
              end

            # Handle removing media (image or video) from gallery association
            {updated_ref, updated_block} =
              cond do
                Map.has_key?(params, :remove_gallery_image_id) ->
                  id = params.remove_gallery_image_id
                  updated_ref = remove_media_from_gallery_ref(updated_ref, :image, id)
                  updated_block = remove_gallery_object_override(updated_block, id)
                  {updated_ref, updated_block}

                Map.has_key?(params, :remove_gallery_video_id) ->
                  id = params.remove_gallery_video_id
                  updated_ref = remove_media_from_gallery_ref(updated_ref, :video, id)
                  updated_block = remove_gallery_object_override(updated_block, id)
                  {updated_ref, updated_block}

                true ->
                  {updated_ref, updated_block}
              end

            # Handle replacing a gallery image (remove old, add new in same position)
            {updated_ref, updated_block} =
              cond do
                Map.has_key?(params, :replace_gallery_image) ->
                  {old_image_id, new_image} = params.replace_gallery_image
                  current_user = %{id: socket.assigns.current_user_id}
                  updated_ref = replace_media_in_gallery_ref(updated_ref, :image, old_image_id, new_image, current_user)
                  updated_block = replace_gallery_media_override(updated_block, old_image_id, new_image.id)
                  {updated_ref, updated_block}

                Map.has_key?(params, :replace_gallery_image_id) ->
                  {old_image_id, new_image_id} = params.replace_gallery_image_id
                  current_user = %{id: socket.assigns.current_user_id}
                  {:ok, new_image} = fetch_media(:image, new_image_id)
                  updated_ref = replace_media_in_gallery_ref(updated_ref, :image, old_image_id, new_image, current_user)
                  updated_block = replace_gallery_media_override(updated_block, old_image_id, new_image_id)
                  {updated_ref, updated_block}

                true ->
                  {updated_ref, updated_block}
              end

            # Update the ref with the modified block data
            updated_ref = Changeset.force_change(updated_ref, :data, updated_block)

            acc ++ List.wrap(updated_ref)
          else
            acc ++ List.wrap(ref)
          end
      end)

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_assoc(block_changeset, :refs, new_refs)
        changeset = Changeset.put_assoc(changeset, :block, updated_block_changeset)
        render_and_update_entry_block_changeset(changeset, entry, has_vars?, has_table_rows?, force_render?)
      else
        changeset = Changeset.put_assoc(changeset, :refs, new_refs)
        render_and_update_block_changeset(changeset, entry, has_vars?, has_table_rows?, force_render?)
      end

    new_form =
      build_form_from_changeset(
        updated_changeset,
        uid,
        belongs_to
      )

    socket = assign(socket, :form, new_form)
    if propagate?, do: send_form_to_parent(socket)

    socket
    |> maybe_reload_or_update_live_preview(media_ref?)
    |> then(&{:ok, &1})
  end

  # update liquid splits for the block editor, and render the module for live preview
  def update(%{event: "update_entry_field", path: path, change: change}, socket) do
    liquid_splits = socket.assigns.liquid_splits
    entry = put_in(socket.assigns.entry, path, change)
    updated_liquid_splits = update_liquid_splits_entry_variables(liquid_splits, entry)

    socket
    |> assign(:entry, entry)
    |> assign(:liquid_splits, updated_liquid_splits)
    |> render_module()
    |> then(&{:ok, &1})
  end

  def update(assigns, socket) do
    changeset = assigns.form.source
    belongs_to = assigns.belongs_to
    block_cs = get_block_changeset(changeset, belongs_to)

    socket
    |> assign(assigns)
    |> assign(:active, Changeset.get_field(changeset, :active))
    |> assign(:deleted, Changeset.get_field(changeset, :marked_as_deleted))
    |> assign(:form_has_changes, changeset.changes !== %{})
    |> assign(:form_is_new, !changeset.data.id)
    |> assign_new(:uid, fn -> Changeset.get_field(block_cs, :uid) end)
    |> assign_new(:path, fn %{uid: uid} -> assigns.parent_path ++ List.wrap(uid) end)
    |> assign_new(:type, fn -> Changeset.get_field(block_cs, :type) end)
    |> assign_new(:multi, fn -> Changeset.get_field(block_cs, :multi) end)
    |> assign_new(:has_vars?, fn ->
      try do
        Changeset.get_assoc(block_cs, :vars) != []
      rescue
        _ -> false
      end
    end)
    |> assign_new(:has_table_rows?, fn ->
      try do
        case Changeset.get_assoc(block_cs, :table_rows) do
          %Ecto.Association.NotLoaded{} -> false
          nil -> false
          [] -> false
          _rows -> true
        end
      rescue
        _ -> false
      end
    end)
    |> assign_new(:parent_id, fn -> Changeset.get_field(block_cs, :parent_id) end)
    |> assign_new(:parent_module_id, fn -> nil end)
    |> assign_new(:containers, fn ->
      Brando.Content.list_containers!(%{
        order: "desc namespace, asc sequence",
        cache: {:ttl, :infinite}
      })
    end)
    |> assign_new(:fragments, fn ->
      Brando.Pages.list_fragments!(%{
        order: "asc language, asc title",
        cache: {:ttl, :infinite}
      })
    end)
    |> assign_new(:collapsed, fn -> Changeset.get_field(changeset, :collapsed) end)
    |> assign_new(:module_id, fn -> Changeset.get_field(block_cs, :module_id) end)
    |> assign_new(:container_id, fn -> Changeset.get_field(block_cs, :container_id) end)
    |> assign_new(:fragment_id, fn -> Changeset.get_field(block_cs, :fragment_id) end)
    |> assign_new(:has_children?, fn -> assigns.children !== [] end)
    |> assign_new(:available_identifiers, fn -> [] end)
    |> assign_new(:original_block_identifiers, fn ->
      # Store original block_identifiers from database for restoring IDs when re-adding
      case block_cs.data.block_identifiers do
        %Ecto.Association.NotLoaded{} -> []
        nil -> []
        identifiers -> identifiers
      end
    end)
    |> assign_new(:module_picker_id, fn ->
      "#block-field-#{assigns.block_field}-module-picker"
    end)
    |> maybe_assign_children()
    |> maybe_assign_module()
    |> maybe_assign_container()
    |> maybe_assign_fragment()
    |> maybe_assign_datasource_meta()
    |> maybe_parse_module()
    |> maybe_render_module()
    |> maybe_get_live_preview_status()
    |> assign(:block_initialized, true)
    |> then(&{:ok, &1})
  end

  defp reset_changesets(socket, block_uid) do
    id = socket.assigns.id
    block_id = "#{id}-child-#{block_uid}"
    send_update(__MODULE__, id: block_id, event: "clear_changesets")
    socket
  end

  def update_changeset_data_block_var(socket, var_key, type, data) when type in [:file, :image] do
    assoc_data = Map.get(data, :type)
    uid = socket.assigns.uid
    changeset = socket.assigns.form.source
    belongs_to = socket.assigns.belongs_to

    update_var_in_changeset(socket, var_key, belongs_to, changeset, uid, type, assoc_data)
  end

  def update_changeset_data_block_var(socket, var_key, :link, data) do
    identifier = Map.get(data, :identifier)
    uid = socket.assigns.uid
    changeset = socket.assigns.form.source
    belongs_to = socket.assigns.belongs_to

    update_var_in_changeset(socket, var_key, belongs_to, changeset, uid, :identifier, identifier)
  end

  def update_changeset_data_block_var(socket, _, _, _), do: socket

  defp update_var_in_changeset(socket, var_key, belongs_to, changeset, uid, data_key, data_value) do
    load_path = get_vars_path(belongs_to)

    # is the block loaded?
    vars = Brando.Utils.try_path(changeset, load_path)
    loaded? = not is_nil(vars) and Ecto.assoc_loaded?(vars)

    if loaded? do
      access_path = get_var_access_path(belongs_to, var_key, data_key)
      updated_changeset = put_in(changeset, access_path, data_value)

      updated_form =
        build_form_from_changeset(
          updated_changeset,
          uid,
          belongs_to
        )

      assign(socket, :form, updated_form)
    else
      socket
    end
  end

  defp get_vars_path(:root), do: [:data, :block, :vars]
  defp get_vars_path(_), do: [:data, :vars]

  defp get_var_access_path(:root, var_key, data_key) do
    [
      Access.key(:data),
      Access.key(:block),
      Access.key(:vars),
      Access.filter(&(&1.key == var_key)),
      Access.key(data_key)
    ]
  end

  defp get_var_access_path(_, var_key, data_key) do
    [
      Access.key(:data),
      Access.key(:vars),
      Access.filter(&(&1.key == var_key)),
      Access.key(data_key)
    ]
  end

  def maybe_get_live_preview_status(%{assigns: %{form_is_new: true, block_initialized: false}} = socket) do
    form_id = socket.assigns.form_id
    block_ref = {__MODULE__, socket.assigns.id}

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      event: "get_live_preview_status",
      block_ref: block_ref
    )

    socket
  end

  def maybe_get_live_preview_status(socket) do
    socket
  end

  def render_module(%{assigns: %{belongs_to: belongs_to}} = socket) do
    changeset = socket.assigns.form.source
    entry = socket.assigns.entry
    has_vars? = socket.assigns.has_vars?
    has_table_rows? = socket.assigns.has_table_rows?

    new_form =
      if belongs_to == :root do
        updated_changeset =
          render_and_update_entry_block_changeset(changeset, entry, has_vars?, has_table_rows?)

        to_form(updated_changeset,
          as: "entry_block",
          id: "entry_block_form-#{socket.assigns.uid}"
        )
      else
        updated_changeset =
          render_and_update_block_changeset(changeset, entry, has_vars?, has_table_rows?)

        to_form(updated_changeset,
          as: "child_block",
          id: "child_block_form-#{socket.assigns.uid}"
        )
      end

    assign(socket, :form, new_form)
  end

  def maybe_render_module(%{assigns: %{belongs_to: :root, live_preview_active?: true}} = socket) do
    update_form_with_rendered_module(socket, :root)
  end

  def maybe_render_module(%{assigns: %{initial_render: false, live_preview_active?: true}} = socket) do
    update_form_with_rendered_module(socket, :child)
  end

  def maybe_render_module(socket) do
    socket
  end

  defp update_form_with_rendered_module(socket, belongs_to_type) do
    changeset = socket.assigns.form.source
    entry = socket.assigns.entry
    uid = socket.assigns.uid
    has_vars? = socket.assigns.has_vars?
    has_table_rows? = socket.assigns.has_table_rows?

    updated_changeset =
      if belongs_to_type == :root do
        render_and_update_entry_block_changeset(changeset, entry, has_vars?, has_table_rows?)
      else
        render_and_update_block_changeset(changeset, entry, has_vars?, has_table_rows?)
      end

    form_type = if belongs_to_type == :root, do: "entry_block", else: "child_block"

    new_form =
      to_form(updated_changeset,
        as: form_type,
        id: "#{form_type}_form-#{uid}"
      )

    assign(socket, :form, new_form)
  end

  def register_block_wanting_entry(block_ref, form_id) do
    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      event: "register_block_wanting_entry",
      block_ref: block_ref
    )
  end

  def maybe_assign_container(%{assigns: %{container_id: nil}} = socket) do
    socket
    |> assign_new(:container, fn -> nil end)
    |> assign_new(:palette_options, fn ->
      Brando.Content.list_palettes!(%{cache: {:ttl, :infinite}})
    end)
  end

  def maybe_assign_container(%{assigns: %{container_id: container_id}} = socket) do
    case get_container(container_id) do
      nil ->
        assign(socket, :container_not_found, true)

      container ->
        socket
        |> assign_new(:container, fn -> container end)
        |> assign_new(:palette_options, fn ->
          if container.allow_custom_palette do
            opts =
              if container.palette_namespace do
                %{
                  filter: %{namespace: container.palette_namespace},
                  cache: {:ttl, :timer.minutes(5)}
                }
              else
                %{cache: {:ttl, :infinite}}
              end

            Brando.Content.list_palettes!(opts)
          else
            []
          end
        end)
    end
  end

  def maybe_assign_fragment(%{assigns: %{fragment_id: nil}} = socket) do
    assign_new(socket, :fragment, fn -> nil end)
  end

  def maybe_assign_fragment(%{assigns: %{fragment_id: fragment_id}} = socket) do
    case get_fragment(fragment_id) do
      nil -> assign(socket, :fragment_not_found, true)
      fragment -> assign_new(socket, :fragment, fn -> fragment end)
    end
  end

  def maybe_assign_datasource_meta(%{assigns: %{is_datasource?: true}} = socket) do
    module_datasource_module = socket.assigns.module_datasource_module
    module_datasource_type = socket.assigns.module_datasource_type
    module_datasource_query = socket.assigns.module_datasource_query

    assign_new(socket, :datasource_meta, fn ->
      Brando.Datasource.get_meta(
        module_datasource_module,
        module_datasource_type,
        module_datasource_query
      )
    end)
  end

  def maybe_assign_datasource_meta(socket) do
    assign_new(socket, :datasource_meta, fn -> nil end)
  end

  def maybe_assign_module(%{assigns: %{module_id: nil}} = socket) do
    socket
    |> assign_new(:module_name, fn -> nil end)
    |> assign_new(:module_class, fn -> nil end)
    |> assign_new(:module_code, fn -> nil end)
    |> assign_new(:module_type, fn -> nil end)
    |> assign_new(:heex_compiled_module, fn -> nil end)
    |> assign_new(:module_color, fn -> :blue end)
    |> assign_new(:is_datasource?, fn -> false end)
    |> assign_new(:has_table_template?, fn -> false end)
    |> assign_new(:table_template, fn -> nil end)
    |> assign_new(:table_template_name, fn -> nil end)
    |> assign_new(:module_datasource_module, fn -> nil end)
    |> assign_new(:module_datasource_module_label, fn -> nil end)
    |> assign_new(:module_datasource_type, fn -> nil end)
    |> assign_new(:module_datasource_query, fn -> nil end)
    |> assign_new(:entry_template, fn -> nil end)
  end

  def maybe_assign_module(%{assigns: %{module_id: module_id}} = socket) do
    case get_module(module_id) do
      nil ->
        assign(socket, :module_not_found, true)

      module ->
        module_datasource_module =
          if module.datasource and module.datasource_module do
            module = Module.concat(List.wrap(module.datasource_module))
            domain = module.__naming__().domain
            schema = module.__naming__().schema

            gettext_module = module.__modules__().gettext
            gettext_domain = String.downcase("#{domain}_#{schema}")
            msgid = Brando.Utils.humanize(module.__naming__().singular, :downcase)

            String.capitalize(Gettext.dgettext(gettext_module, gettext_domain, msgid))
          else
            ""
          end

        socket
        |> assign_new(:module_name, fn -> module.name end)
        |> assign_new(:module_class, fn -> module.class end)
        |> assign_new(:module_code, fn -> module.code end)
        |> assign_new(:module_type, fn -> module.type end)
        |> assign_new(:heex_compiled_module, fn -> nil end)
        |> assign_new(:module_color, fn -> module.color end)
        |> assign_new(:is_datasource?, fn -> module.datasource end)
        |> assign_new(:has_table_template?, fn -> (module.table_template_id && true) || false end)
        |> assign_new(:table_template, fn ->
          table_template_id = module.table_template_id

          if table_template_id do
            {:ok, table_template} =
              Brando.Content.get_table_template(%{
                matches: %{id: table_template_id},
                preload: [vars: [:file, :image, :palette, :identifier, :menu_item]]
              })

            table_template
          end
        end)
        |> assign_new(:table_template_name, fn %{table_template: table_template} ->
          if table_template do
            table_template.name
          end
        end)
        |> assign_new(:module_datasource_module, fn -> module.datasource_module end)
        |> assign_new(:module_datasource_module_label, fn -> module_datasource_module end)
        |> assign_new(:module_datasource_type, fn -> module.datasource_type end)
        |> assign_new(:module_datasource_query, fn -> module.datasource_query end)
        |> assign_new(:entry_template, fn -> module.entry_template end)
        |> maybe_register_block_wanting_entry()
    end
  end

  def maybe_register_block_wanting_entry(%{assigns: %{block_initialized: false, is_datasource?: true}} = socket) do
    block_ref = {__MODULE__, socket.assigns.id}
    form_id = socket.assigns.form_id

    register_block_wanting_entry(block_ref, form_id)
    socket
  end

  def maybe_register_block_wanting_entry(%{assigns: %{block_initialized: false}} = socket) do
    # check if the module code contains any entry variables. these can be in for loops, if/unless,
    # assign statements, or in the module code itself
    module_code = socket.assigns.module_code

    if Regex.run(~r/(?:entry\.|@entry\.)[\w]+/, module_code) do
      block_ref = {__MODULE__, socket.assigns.id}
      form_id = socket.assigns.form_id

      register_block_wanting_entry(block_ref, form_id)
    end

    socket
  end

  def maybe_register_block_wanting_entry(socket), do: socket

  defp maybe_parse_module(%{assigns: %{module_not_found: true}} = socket), do: socket

  defp maybe_parse_module(%{assigns: %{module_code: module_code, module_type: :liquid} = assigns} = socket) do
    block_initialized = assigns.block_initialized

    if block_initialized do
      socket
    else
      module_code =
        module_code
        |> liquid_strip_logic()
        |> emphasize_datasources(assigns)

      belongs_to = socket.assigns.belongs_to
      changeset = socket.assigns.form.source
      entry = socket.assigns.entry
      changeset = maybe_preload_changeset_data(changeset, :vars, belongs_to)

      vars =
        if belongs_to == :root do
          changeset
          |> Changeset.get_field(:block)
          |> Changeset.change()
          |> Changeset.get_assoc(:vars)
        else
          Changeset.get_assoc(changeset, :vars)
        end

      splits =
        ~r/{% (?:ref|headless_ref) refs.(\w+) %}|<.*?>|\{\{\s?(.*?)\s?\}\}|{% picture ([a-zA-Z0-9_.?|"-]+) {.*} %}/
        |> Regex.split(module_code, include_captures: true)
        |> Enum.map(fn chunk ->
          case Regex.run(
                 ~r/^{% (?:ref|headless_ref) refs.(?<ref>\w+) %}$|^{{ (?<content>[\w\s.|\"\']+) }}$|^{% picture (?<picture>[a-zA-Z0-9_.?|"-]+) {.*} %}$/,
                 chunk,
                 capture: :all_names
               ) do
            nil ->
              chunk

            ["content", "", ""] ->
              {:content, "content"}

            ["content | renderless", "", ""] ->
              {:content, "content"}

            ["entry." <> variable, "", ""] ->
              {:entry_variable, variable, liquid_render_entry_variable(variable, entry)}

            [module_variable, "", ""] ->
              {:module_variable, module_variable, liquid_render_module_variable(module_variable, vars)}

            ["", "entry." <> pic = pic_var, ""] ->
              {:entry_picture, pic_var, liquid_render_entry_picture_src(pic, socket.assigns)}

            ["", pic, ""] ->
              {:module_picture, pic, liquid_render_module_picture_src(pic, vars)}

            ["", "", ref] ->
              {:ref, ref}
          end
        end)

      socket
      |> assign(:liquid_splits, splits)
      |> assign(:vars, vars)
    end
  end

  defp maybe_parse_module(%{assigns: %{module_code: module_code, module_type: :heex} = assigns} = socket) do
    block_initialized = assigns.block_initialized

    if block_initialized do
      socket
    else
      belongs_to = socket.assigns.belongs_to
      changeset = socket.assigns.form.source
      changeset = maybe_preload_changeset_data(changeset, :vars, belongs_to)

      vars =
        if belongs_to == :root do
          changeset
          |> Changeset.get_field(:block)
          |> Changeset.change()
          |> Changeset.get_assoc(:vars)
        else
          Changeset.get_assoc(changeset, :vars)
        end

      heex_compiled_module =
        try do
          Brando.Villain.HeexRenderer.get_or_compile!(
            "admin_#{socket.assigns.uid}",
            module_code
          )
        rescue
          # credo:disable-for-next-line ExSlop.Check.Warning.RescueWithoutReraise
          e ->
            require Logger
            Logger.warning("Failed to compile HEEx module template: #{Exception.message(e)}")
            nil
        end

      socket
      |> assign(:liquid_splits, [])
      |> assign(:vars, vars)
      |> assign(:heex_compiled_module, heex_compiled_module)
    end
  end

  defp maybe_parse_module(socket) do
    assign(socket, liquid_splits: [], vars: [])
  end

  # if the assoc is not preloaded, meaning it is an %Ecto.Association.NotLoaded{} struct,
  # we preload it and stick it in the data field. My least favorite part of dealing with
  # changesets + revisions
  defp maybe_preload_changeset_data(changeset, assoc, :root) do
    if assoc_is_loaded(get_in(changeset, [Access.key(:data), Access.key(:block), Access.key(:vars)])) do
      changeset
    else
      update_in(changeset.data.block, &Brando.Repo.repo().preload(&1, assoc))
    end
  end

  defp maybe_preload_changeset_data(changeset, assoc, _) do
    if assoc_is_loaded(get_in(changeset, [Access.key(:data), Access.key(:vars)])) do
      changeset
    else
      update_in(changeset.data, &Brando.Repo.repo().preload(&1, assoc))
    end
  end

  defp assoc_is_loaded(%Ecto.Association.NotLoaded{}), do: false
  defp assoc_is_loaded(_), do: true

  defdelegate reset_position_response_tracker(socket),
    to: BrandoAdmin.Components.Form.BlockChangesetList

  # after we've sent messages to block asking for position updates, if we have deleted the
  # last child block, we refresh the live preview
  defp update_live_preview_on_empty_block_list(%{assigns: %{block_list: []}} = socket) do
    form_id = socket.assigns.form_id
    send_update(BrandoAdmin.Components.Form, id: form_id, event: "update_live_preview")
    socket
  end

  defp update_live_preview_on_empty_block_list(socket) do
    socket
  end

  def assign_available_identifiers(socket) do
    module = Module.concat([socket.assigns.module_datasource_module])
    query = socket.assigns.module_datasource_query
    entry = socket.assigns.entry

    {:ok, available_identifiers} =
      Brando.Datasource.list_results(
        module,
        query,
        socket.assigns.vars,
        Map.get(entry, :language)
      )

    assign(socket, :available_identifiers, available_identifiers)
  end

  # we don't touch children_forms if the block is already initialized
  def maybe_assign_children(%{assigns: %{block_initialized: true}} = socket), do: socket

  def maybe_assign_children(%{assigns: %{children: []}} = socket) do
    socket
    |> assign_new(:block_list, fn -> [] end)
    |> assign_new(:changesets, fn -> [] end)
    |> assign_new(:block_count, fn -> 0 end)
    |> assign(:children_forms, [])
  end

  def maybe_assign_children(%{assigns: %{type: :container}} = socket),
    do: do_assign_children(socket)

  def maybe_assign_children(%{assigns: %{type: :module, multi: true}} = socket),
    do: do_assign_children(socket)

  def maybe_assign_children(socket) do
    socket
    |> assign_new(:block_count, fn -> 0 end)
    |> assign_new(:block_list, fn -> [] end)
    |> assign_new(:changesets, fn -> [] end)
  end

  defp do_assign_children(%{assigns: %{children: children}} = socket) do
    current_user_id = socket.assigns.current_user_id

    children_forms =
      Enum.map(
        children,
        &to_change_form(&1, %{}, current_user_id)
      )

    socket
    |> assign(:children_forms, children_forms)
    |> assign_new(:block_count, fn -> Enum.count(children) end)
    |> assign_new(:changesets, fn -> Enum.map(children, &{extract_uid(&1), nil}) end)
    |> assign_new(:block_list, fn -> Enum.map(children, &extract_uid(&1)) end)
  end

  defp extract_uid(%{uid: uid}), do: uid

  defp extract_uid(%Ecto.Changeset{} = cs) do
    Ecto.Changeset.get_field(cs, :uid)
  end

  def send_child_position_update(socket, block_list) do
    # send_update to all components in block_list
    parent_id = socket.assigns.id

    for {block_uid, idx} <- Enum.with_index(block_list) do
      id = "#{parent_id}-child-#{block_uid}"
      send_update(__MODULE__, id: id, event: "update_sequence", sequence: idx)
    end

    socket
  end

  defdelegate update_child_changeset(changesets, uid, new_changeset),
    to: BrandoAdmin.Components.Form.BlockChangesetList,
    as: :update_changeset

  defdelegate insert_child_changeset(changesets, uid, position),
    to: BrandoAdmin.Components.Form.BlockChangesetList,
    as: :insert_changeset

  defdelegate delete_child_changeset(changesets, uid),
    to: BrandoAdmin.Components.Form.BlockChangesetList,
    as: :delete_changeset

  defp put_children(changeset, children_list) do
    actioned_children = Enum.map(children_list, &Brando.Utils.set_action/1)

    if changeset.data.__struct__ == Brando.Content.Block do
      Changeset.put_assoc(changeset, :children, actioned_children)
    else
      updated_block_changeset =
        changeset
        |> Changeset.get_assoc(:block)
        |> Changeset.put_assoc(:children, actioned_children)

      Changeset.put_assoc(changeset, :block, updated_block_changeset)
    end
  end

  ## Render delegation
  ## All render/1 clauses and function components live in Block.Render.
  ## Externally-used components are delegated below for backwards compatibility.

  defdelegate render(assigns), to: __MODULE__.Render
  defdelegate plus(assigns), to: __MODULE__.Render
  defdelegate block(assigns), to: __MODULE__.Render
  defdelegate ref(assigns), to: __MODULE__.Render

  def should_force_live_preview_update?(changeset, updated_changeset, :root) do
    block_changeset = Changeset.get_assoc(changeset, :block)
    updated_block_changeset = Changeset.get_assoc(updated_changeset, :block)

    Changeset.get_field(block_changeset, :type) == :container &&
      Changeset.get_field(block_changeset, :active) == false &&
      Changeset.get_field(updated_block_changeset, :active) == true
  end

  @doc """
  Build a form from a changeset based on whether it belongs to the root or not.
  """
  def build_form_from_changeset(changeset, uid, belongs_to) do
    if belongs_to == :root do
      to_form(changeset,
        as: "entry_block",
        id: "entry_block_form-#{uid}"
      )
    else
      to_form(changeset,
        as: "child_block",
        id: "child_block_form-#{uid}"
      )
    end
  end

  def maybe_put_empty_children(changeset, false) do
    updated_block_cs =
      changeset
      |> Changeset.get_assoc(:block)
      |> Changeset.put_assoc(:children, [])

    Changeset.put_assoc(changeset, :block, updated_block_cs)
  end

  def maybe_put_empty_children(changeset, true) do
    changeset
  end

  def send_form_to_parent(socket) do
    parent_ref = socket.assigns.parent_ref
    level = socket.assigns.level
    form = socket.assigns.form

    send_to_ref(parent_ref, %{event: "update_block", level: level, form: form})
    socket
  end

  # A media association on a ref changed (image/video/gallery/file selected, swapped
  # or cleared). The new player must be mounted by the host frontend's JS, which a
  # block-level morphdom can't do — it would swap in inert markup and leave a gray
  # box. So fall back to a full live-preview reload (the form re-mints the cache key,
  # the iframe reloads, the frontend boots the player) — the same path used on open.
  # Non-media ref edits (captions, text) stay on the cheap block-level morphdom path.
  defp maybe_reload_or_update_live_preview(%{assigns: %{live_preview_active?: true}} = socket, true) do
    send_update(BrandoAdmin.Components.Form,
      id: socket.assigns.form_id,
      event: "reload_live_preview"
    )

    socket
  end

  defp maybe_reload_or_update_live_preview(socket, _media_ref?) do
    maybe_update_live_preview_block(socket)
  end

  # Keys in an update_ref_data payload that introduce, swap or remove a media
  # association whose frontend player must be JS-mounted (video/gallery/image/file).
  defp media_ref_change?(params) do
    Enum.any?(
      [
        :image_id,
        :video_id,
        :gallery_id,
        :file_id,
        :video_data,
        :add_gallery_image_id,
        :add_gallery_video_id,
        :remove_gallery_image_id,
        :remove_gallery_video_id,
        :replace_gallery_image,
        :replace_gallery_image_id
      ],
      &Map.has_key?(params, &1)
    )
  end

  def maybe_update_live_preview_block(%{assigns: %{live_preview_active?: true}} = socket) do
    %{
      form: %{source: changeset},
      belongs_to: belongs_to,
      has_children?: has_children?,
      form_id: form_id
    } = socket.assigns

    block_cs = get_block_changeset(changeset, belongs_to)
    rendered_html = Changeset.get_field(block_cs, :rendered_html)
    uid = Changeset.get_field(block_cs, :uid)

    send_update(BrandoAdmin.Components.Form,
      id: form_id,
      event: "update_live_preview_block",
      rendered_html: rendered_html,
      uid: uid,
      has_children?: has_children?
    )

    socket
  end

  def maybe_update_live_preview_block(socket), do: socket

  def get_fragment(nil), do: nil

  def get_fragment(id) do
    Brando.Pages.get_fragment!(%{
      matches: %{id: id}
    })
  end

  defdelegate get_container(id), to: Brando.Content, as: :fetch_container
  defdelegate get_module(id), to: Brando.Content, as: :fetch_module

  def render_and_update_entry_block_changeset(changeset, entry, has_vars?, has_table_rows?, force_render? \\ false) do
    skip_children =
      if force_render? do
        :force_render
      else
        true
      end

    rendered_html = render_block_html(changeset, entry, has_vars?, has_table_rows?, true, skip_children)

    updated_block_changeset =
      changeset
      |> Changeset.get_assoc(:block)
      |> Changeset.put_change(:rendered_html, rendered_html)
      |> maybe_update_rendered_at()

    Changeset.put_assoc(changeset, :block, updated_block_changeset)
  end

  def render_and_update_block_changeset(changeset, entry, has_vars?, has_table_rows?, force_render? \\ false) do
    skip_children = if force_render?, do: :force_render, else: true
    rendered_html = render_block_html(changeset, entry, has_vars?, has_table_rows?, false, skip_children)

    changeset
    |> Changeset.put_change(:rendered_html, rendered_html)
    |> maybe_update_rendered_at()
  end

  defp render_block_html(changeset, entry, has_vars?, has_table_rows?, is_root, skip_children) do
    changeset
    |> Brando.Utils.apply_changes_recursively()
    |> reset_empty_vars(has_vars?, is_root)
    |> reset_table_rows(has_table_rows?, is_root)
    |> ensure_gallery_associations_loaded(is_root)
    |> Brando.Villain.render_block(entry,
      skip_children: skip_children,
      format_html: true,
      annotate_blocks: true
    )
  end

  # Ensure gallery objects have their image/video associations loaded for live preview
  # This only modifies the struct for rendering - never touches the persistence changeset
  defp ensure_gallery_associations_loaded(block, true) do
    case get_in(block, [Access.key(:block), Access.key(:refs)]) do
      nil ->
        block

      %Ecto.Association.NotLoaded{} ->
        block

      refs when is_list(refs) ->
        put_in(block, [Access.key(:block), Access.key(:refs)], load_galleries_in_refs(refs))

      _ ->
        block
    end
  end

  defp ensure_gallery_associations_loaded(block, false) do
    case Map.get(block, :refs) do
      nil -> block
      %Ecto.Association.NotLoaded{} -> block
      refs when is_list(refs) -> Map.put(block, :refs, load_galleries_in_refs(refs))
      _ -> block
    end
  end

  defp load_galleries_in_refs(refs) do
    Enum.map(refs, fn ref ->
      case Map.get(ref, :gallery) do
        nil -> ref
        %Ecto.Association.NotLoaded{} -> ref
        gallery -> Map.put(ref, :gallery, load_gallery_objects(gallery))
      end
    end)
  end

  defp load_gallery_objects(gallery) do
    case Map.get(gallery, :gallery_objects) do
      nil -> gallery
      %Ecto.Association.NotLoaded{} -> gallery
      objects when is_list(objects) -> Map.put(gallery, :gallery_objects, Enum.map(objects, &load_media/1))
      _ -> gallery
    end
  end

  defp load_media(obj) do
    obj
    |> maybe_load_image()
    |> maybe_load_video()
  end

  defp maybe_load_image(obj) do
    case {Map.get(obj, :image_id), Map.get(obj, :image)} do
      {nil, _} ->
        obj

      {_, %{id: _}} ->
        obj

      {image_id, _} ->
        case Brando.Images.get_image(image_id) do
          {:ok, image} -> Map.put(obj, :image, image)
          _ -> obj
        end
    end
  end

  defp maybe_load_video(obj) do
    case {Map.get(obj, :video_id), Map.get(obj, :video)} do
      {nil, _} ->
        obj

      {_, %{id: _}} ->
        obj

      {video_id, _} ->
        case Brando.Videos.get_video(video_id) do
          {:ok, video} -> Map.put(obj, :video, video)
          _ -> obj
        end
    end
  end

  defp maybe_update_rendered_at(%Changeset{changes: %{rendered_html: _}} = changeset) do
    Changeset.put_change(changeset, :rendered_at, DateTime.truncate(DateTime.utc_now(), :second))
  end

  defp maybe_update_rendered_at(changeset) do
    changeset
  end

  defp reset_empty_vars(block, true, _), do: block

  # if we don't have vars, force them to an empty list, since they get set to NotLoaded.
  defp reset_empty_vars(block, false, true) do
    put_in(block, [Access.key(:block), Access.key(:vars)], [])
  end

  defp reset_empty_vars(block, false, false) do
    put_in(block, [Access.key(:vars)], [])
  end

  defp reset_table_rows(block, true, _), do: block

  # if we don't have vars, force them to an empty list, since they get set to NotLoaded.
  defp reset_table_rows(block, false, true) do
    put_in(block, [Access.key(:block), Access.key(:table_rows)], [])
  end

  defp reset_table_rows(block, false, false) do
    put_in(block, [Access.key(:table_rows)], [])
  end

  def update_liquid_splits_entry_variables(liquid_splits, entry) do
    liquid_splits
    |> Enum.reduce([], fn
      {:entry_variable, variable, _}, acc ->
        [{:entry_variable, variable, liquid_render_entry_variable(variable, entry)} | acc]

      item, acc ->
        [item | acc]
    end)
    |> Enum.reverse()
  end

  def maybe_update_container(socket, [_block_type, "block", "container_id"]) do
    changeset = socket.assigns.form.source
    block_cs = Changeset.get_assoc(changeset, :block)
    container_id = Changeset.get_field(block_cs, :container_id)
    assign(socket, :container, get_container(container_id))
  end

  def maybe_update_container(socket, _), do: socket

  def maybe_update_fragment(socket, [_block_type, "block", "fragment_id"]) do
    changeset = socket.assigns.form.source
    block_cs = Changeset.get_assoc(changeset, :block)
    fragment_id = Changeset.get_field(block_cs, :fragment_id)
    assign(socket, :fragment, get_fragment(fragment_id))
  end

  def maybe_update_fragment(socket, _), do: socket

  # if the target param updated is a var and it's not an image or file, we extract the value
  # and update the liquex block var
  def maybe_update_liquex_block_var(socket, [_block_type, "vars", _idx, "value"] = params_target, params) do
    var_target =
      params_target
      |> List.delete_at(0)
      |> List.delete_at(-1)

    var_params = get_in(params, var_target)
    value = Map.get(var_params, "value")
    var_key = Map.get(var_params, "key")

    var_type =
      var_params
      |> Map.get("type")
      |> String.to_existing_atom()

    update_liquex_block_var(socket, var_key, var_type, %{value: value})
  end

  def maybe_update_liquex_block_var(socket, _, _), do: socket

  def update_liquex_block_var(socket, var_key, :image, data) do
    path = get_in(data, [:image, Access.key(:path)])
    media_path = Brando.Utils.media_url(path)
    update_liquid_split_var(socket, var_key, media_path)
  end

  def update_liquex_block_var(socket, var_key, _var_type, data) do
    update_liquid_split_var(socket, var_key, Map.get(data, :value))
  end

  defp update_liquid_split_var(socket, var_key, new_value) do
    liquid_splits = socket.assigns.liquid_splits

    updated_liquid_splits =
      liquid_splits
      |> Enum.reduce([], fn
        {type, ^var_key, _prev_var_value}, acc ->
          [{type, var_key, new_value} | acc]

        item, acc ->
          [item | acc]
      end)
      |> Enum.reverse()

    assign(socket, :liquid_splits, updated_liquid_splits)
  end

  defp to_change_form(child_block_or_cs, params, user, action \\ nil) do
    changeset =
      child_block_or_cs
      |> Brando.Content.Block.block_changeset(params, user)
      |> Map.put(:action, action)

    uid = Changeset.get_field(changeset, :uid)

    to_form(changeset,
      as: "child_block",
      id: "child_block_form-#{uid}"
    )
  end

  defp emphasize_datasources(code, assigns) do
    Regex.replace(
      ~r/(({% datasource %}(?:.*?){% enddatasource %}))/s,
      code,
      """
      <div class="brando-datasource-placeholder">
         <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24"><path fill="none" d="M0 0h24v24H0z"/><path d="M5 12.5c0 .313.461.858 1.53 1.393C7.914 14.585 9.877 15 12 15c2.123 0 4.086-.415 5.47-1.107 1.069-.535 1.53-1.08 1.53-1.393v-2.171C17.35 11.349 14.827 12 12 12s-5.35-.652-7-1.671V12.5zm14 2.829C17.35 16.349 14.827 17 12 17s-5.35-.652-7-1.671V17.5c0 .313.461.858 1.53 1.393C7.914 19.585 9.877 20 12 20c2.123 0 4.086-.415 5.47-1.107 1.069-.535 1.53-1.08 1.53-1.393v-2.171zM3 17.5v-10C3 5.015 7.03 3 12 3s9 2.015 9 4.5v10c0 2.485-4.03 4.5-9 4.5s-9-2.015-9-4.5zm9-7.5c2.123 0 4.086-.415 5.47-1.107C18.539 8.358 19 7.813 19 7.5c0-.313-.461-.858-1.53-1.393C16.086 5.415 14.123 5 12 5c-2.123 0-4.086.415-5.47 1.107C5.461 6.642 5 7.187 5 7.5c0 .313.461.858 1.53 1.393C7.914 9.585 9.877 10 12 10z"/></svg>
         <div class="text-mono">#{assigns.module_datasource_module_label} | #{assigns.module_datasource_type} | #{assigns.module_datasource_query}</div>
         #{gettext("Content from datasource will be inserted here")}
      </div>
      """
    )
  end

  defp liquid_strip_logic(module_code) do
    Regex.replace(
      ~r/(({% hide %}(?:.*?){% endhide %}))|((?:{%(?:-)? for (\w+) in [a-zA-Z0-9_.?|"-]+ (?:-)?%})(?:.*?)(?:{%(?:-)? endfor (?:-)?%}))|(<img.*?src="{{(?:-)? .*? (?:-)?}}".*?>)|({%(?:-)? assign .*? (?:-)?%})|(((?:{%(?:-)? if .*? (?:-)?%})(?:.*?)(?:{%(?:-)? endif (?:-)?%})))|(((?:{%(?:-)? unless .*? (?:-)?%})(?:.*?)(?:{%(?:-)? endunless (?:-)?%})))|(data-moonwalk-run(?:="\w+")|data-moonwalk-run|data-moonwalk-section(?:="\w+")|data-moonwalk-section|href(?:="[a-zA-Z0-9{}|._\s]+")|id(?:="{{[a-zA-Z0-9{}._\s]+}}"))/s,
      module_code,
      ""
    )
  end

  defp liquid_render_entry_picture_src("entry." <> var_path_string, assigns) do
    entry = assigns.entry

    var_path =
      var_path_string
      |> String.split(".")
      |> Enum.map(&String.to_existing_atom/1)

    case Brando.Utils.try_path(entry, var_path ++ [:path]) do
      nil -> ""
      path -> Brando.Utils.media_url(path)
    end
  end

  defp liquid_render_module_picture_src(var_name, vars) do
    case Enum.find(vars, &(Changeset.get_field(&1, :key) == var_name)) do
      nil ->
        ""

      var_cs ->
        image_id = Changeset.get_field(var_cs, :image_id)
        image = Changeset.get_field(var_cs, :image)

        cond do
          image_id == nil ->
            ""

          image == %Ecto.Association.NotLoaded{} ->
            image_id = Changeset.get_field(var_cs, :image_id)

            case Brando.Cache.get("var_image_#{image_id}") do
              nil ->
                image = Brando.Images.get_image!(image_id)
                media_path = Brando.Utils.media_url(image.path)
                Brando.Cache.put("var_image_#{image_id}", media_path, :timer.minutes(3))
                media_path

              media_path ->
                media_path
            end

          is_struct(image, Brando.Images.Image) ->
            path = image.path
            media_path = Brando.Utils.media_url(path)
            Brando.Cache.put("var_image_#{image_id}", media_path, :timer.minutes(3))
            media_path

          true ->
            require Logger

            Logger.error("""

            other:
            #{inspect(image_id, pretty: true)}
            #{inspect(image, pretty: true)}

            """)

            ""
        end
    end
  end

  defp liquid_render_entry_variable(var_path_string, entry) do
    var_path =
      var_path_string
      |> String.split(".")
      |> Enum.map(&String.to_existing_atom/1)

    entry |> Brando.Utils.try_path(var_path) |> raw()
  rescue
    ArgumentError ->
      "{{ entry.#{var_path_string} }}"
  end

  defp liquid_render_module_variable(var, vars) do
    case Enum.find(vars, &(Changeset.get_field(&1, :key) == var)) do
      nil -> var
      var_cs -> Changeset.get_field(var_cs, :value)
    end
  end

  @doc """
  Inserts an identifier into the block_identifiers list.

  If the identifier previously existed in the original data (was persisted),
  we include its id so Ecto treats it as an update rather than insert.
  This prevents unique constraint violations when re-adding removed identifiers.

  The sequence is set to place the new identifier at the end of the list.
  """
  def insert_identifier(block_identifiers, identifier_id, original_identifiers \\ []) do
    # Check if this identifier was previously persisted
    existing = Enum.find(original_identifiers, &(&1.identifier_id == identifier_id && &1.id))

    # Calculate new sequence (highest current sequence + 1)
    new_sequence = get_next_sequence(block_identifiers)

    new_block_identifier =
      if existing,
        do: %{id: existing.id, identifier_id: identifier_id, sequence: new_sequence},
        else: %{identifier_id: identifier_id, sequence: new_sequence}

    block_identifiers ++ [new_block_identifier]
  end

  defp get_next_sequence(block_identifiers) do
    block_identifiers
    |> Enum.map(&Changeset.get_field(&1, :sequence))
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> 0
      sequences -> Enum.max(sequences) + 1
    end
  end

  def remove_identifier(block_identifiers, identifier_id) do
    Enum.reject(
      block_identifiers,
      &(Changeset.get_field(&1, :identifier_id) == identifier_id)
    )
  end

  @doc """
  Updates a block changeset based on whether it belongs to the root or not.
  """
  def update_block_changeset(changeset, block_changeset, :root) do
    Changeset.put_assoc(changeset, :block, block_changeset)
  end

  def update_block_changeset(_changeset, block_changeset, _) do
    block_changeset
  end

  def get_block_data_changeset(block) do
    Changeset.get_embed(block[:data].form.source, :data)
  end

  @doc """
  Gets the block changeset depending on whether it belongs to the root or not.
  """
  def get_block_changeset(changeset, :root), do: Changeset.get_assoc(changeset, :block)
  def get_block_changeset(changeset, _), do: changeset

  defp clear_preloaded_associations(changeset, params) do
    # Clear stale preloaded associations when updating foreign keys
    # This ensures the parser gets consistent data by setting the association to nil
    # rather than deleting the field entirely
    changeset =
      if Map.has_key?(params, :image_id) do
        # Clear the preloaded :image association since we're updating image_id
        Map.put(changeset, :data, Map.put(changeset.data, :image, nil))
      else
        changeset
      end

    changeset =
      if Map.has_key?(params, :video_id) do
        # Clear the preloaded :video association since we're updating video_id
        Map.put(changeset, :data, Map.put(changeset.data, :video, nil))
      else
        changeset
      end

    changeset =
      if Map.has_key?(params, :gallery_id) do
        # Clear the preloaded :gallery association since we're updating gallery_id
        Map.put(changeset, :data, Map.put(changeset.data, :gallery, nil))
      else
        changeset
      end

    changeset =
      if Map.has_key?(params, :file_id) do
        # Clear the preloaded :file association since we're updating file_id
        Map.put(changeset, :data, Map.put(changeset.data, :file, nil))
      else
        changeset
      end

    changeset
  end

  defp put_change_if_key_exists(changeset, key, params) do
    if Map.has_key?(params, key) do
      Changeset.put_change(changeset, key, normalize_media_id(params[key]))
    else
      changeset
    end
  end

  # Media id keys (image_id/video_id/gallery_id/file_id) are `:id` fields, but these
  # values arrive straight from the client (e.g. a picker) as strings and are written
  # with `put_change`, which does NOT cast — so a string id reaches Ecto and blows up
  # on insert. Coerce to an integer here; "" / nil mean "clear the association".
  defp normalize_media_id(nil), do: nil
  defp normalize_media_id(""), do: nil
  defp normalize_media_id(id) when is_integer(id), do: id

  defp normalize_media_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {int, ""} -> int
      _ -> nil
    end
  end

  # Add an image to a gallery ref association
  defp add_media_to_gallery_ref(ref_changeset, media_type, media_id, current_user) do
    current_gallery = Changeset.get_field(ref_changeset, :gallery)

    {:ok, media} =
      case fetch_media(media_type, media_id) do
        {:ok, _} = result ->
          result

        {:error, reason} ->
          raise "add_media_to_gallery_ref: failed to fetch #{media_type} with id #{inspect(media_id)}: #{inspect(reason)}"
      end

    new_gallery_object =
      %{creator_id: current_user.id}
      |> put_media_fields(media_type, media_id, media)

    case current_gallery do
      nil ->
        new_gallery = %{
          config_target: "ref:gallery",
          gallery_objects: [Map.put(new_gallery_object, :sequence, 0)]
        }

        Changeset.put_assoc(ref_changeset, :gallery, new_gallery)

      gallery ->
        current_gallery_objects =
          Enum.map(gallery.gallery_objects || [], &preserve_gallery_object/1)

        new_gallery_objects = current_gallery_objects ++ [new_gallery_object]

        updated_gallery = %{
          id: Map.get(gallery, :id),
          config_target: Map.get(gallery, :config_target, "ref:gallery"),
          gallery_objects: sequence_gallery_objects(new_gallery_objects)
        }

        Changeset.put_assoc(ref_changeset, :gallery, updated_gallery)
    end
  end

  defp remove_media_from_gallery_ref(ref_changeset, media_type, media_id) do
    current_gallery = Changeset.get_field(ref_changeset, :gallery)
    id_field = media_id_field(media_type)

    case current_gallery do
      nil ->
        ref_changeset

      gallery ->
        existing_objects = gallery.gallery_objects || []
        updated_objects = Enum.reject(existing_objects, &(Map.get(&1, id_field) == media_id))

        if updated_objects == [] do
          Changeset.put_assoc(ref_changeset, :gallery, nil)
        else
          updated_gallery = %{
            id: Map.get(gallery, :id),
            config_target: Map.get(gallery, :config_target, "ref:gallery"),
            gallery_objects: sequence_gallery_objects(updated_objects)
          }

          Changeset.put_assoc(ref_changeset, :gallery, updated_gallery)
        end
    end
  end

  # Replace a media item in a gallery ref association (same position).
  # `new_media` is the full struct (avoids re-fetching from DB).
  defp replace_media_in_gallery_ref(ref_changeset, media_type, old_media_id, new_media, current_user) do
    current_gallery = Changeset.get_field(ref_changeset, :gallery)
    id_field = media_id_field(media_type)
    new_media_id = new_media.id

    case current_gallery do
      nil ->
        ref_changeset

      gallery ->
        existing_objects = gallery.gallery_objects || []

        updated_objects =
          Enum.map(existing_objects, fn obj ->
            if Map.get(obj, id_field) == old_media_id do
              %{creator_id: current_user.id}
              |> put_media_fields(media_type, new_media_id, new_media)
            else
              preserve_gallery_object(obj)
            end
          end)

        updated_gallery = %{
          id: Map.get(gallery, :id),
          config_target: Map.get(gallery, :config_target, "ref:gallery"),
          gallery_objects: sequence_gallery_objects(updated_objects)
        }

        Changeset.put_assoc(ref_changeset, :gallery, updated_gallery)
    end
  end

  defp replace_gallery_media_override(block_changeset, old_media_id, new_media_id) do
    current_data = Changeset.get_field(block_changeset, :data)
    {current_overrides, data_map} = extract_gallery_data(current_data)
    old_id_str = to_string(old_media_id)
    new_id_str = to_string(new_media_id)

    updated_overrides =
      Enum.map(current_overrides, fn override ->
        if get_override_object_id(override) == old_id_str do
          case override do
            %Changeset{} -> Changeset.put_change(override, :object_id, new_id_str)
            %{} -> Map.put(override, :object_id, new_id_str)
          end
        else
          override
        end
      end)

    updated_data_map = Map.put(data_map, :gallery_object_overrides, updated_overrides)
    Changeset.put_change(block_changeset, :data, updated_data_map)
  end

  # Note: Removed create_gallery_with_image and add_image_to_existing_gallery
  # These are now handled inline in add_image_to_gallery_ref using changesets

  defp sequence_gallery_objects(gallery_objects) do
    gallery_objects
    |> Enum.with_index()
    |> Enum.map(fn {obj, index} -> Map.put(obj, :sequence, index) end)
  end

  defp maybe_add_association(base_fields, :image, obj) do
    # Always re-fetch from DB to avoid stale data (e.g. unprocessed images
    # stored in changeset that have since been processed)
    case Map.get(obj, :image_id) do
      nil ->
        base_fields

      id ->
        case Brando.Images.get_image(id) do
          {:ok, image} -> Map.put(base_fields, :image, image)
          _ -> base_fields
        end
    end
  end

  defp maybe_add_association(base_fields, :video, obj) do
    case Map.get(obj, :video) do
      %Ecto.Association.NotLoaded{} ->
        # Re-fetch if we have the ID
        case Map.get(obj, :video_id) do
          nil ->
            base_fields

          id ->
            case Brando.Videos.get_video(%{matches: %{id: id}, preload: [:thumbnail]}) do
              {:ok, video} -> Map.put(base_fields, :video, video)
              _ -> base_fields
            end
        end

      nil ->
        base_fields

      video ->
        Map.put(base_fields, :video, video)
    end
  end

  defp add_gallery_media_override(block_changeset, media_id, media_type) do
    current_data = Changeset.get_field(block_changeset, :data)
    {current_overrides, data_map} = extract_gallery_data(current_data)
    object_id_str = to_string(media_id)

    override_exists =
      Enum.any?(current_overrides, fn override ->
        get_override_object_id(override) == object_id_str
      end)

    if override_exists do
      block_changeset
    else
      new_override = %{
        object_id: object_id_str,
        object_type: media_type,
        title: nil,
        credits: nil,
        alt: nil,
        use_default_title: true,
        use_default_credits: true,
        use_default_alt: true
      }

      updated_overrides = current_overrides ++ [new_override]
      updated_data_map = Map.put(data_map, :gallery_object_overrides, updated_overrides)
      Changeset.put_change(block_changeset, :data, updated_data_map)
    end
  end

  defp remove_gallery_object_override(block_changeset, object_id) do
    current_data = Changeset.get_field(block_changeset, :data)
    {current_overrides, data_map} = extract_gallery_data(current_data)
    object_id_str = to_string(object_id)

    updated_overrides =
      Enum.reject(current_overrides, fn override ->
        get_override_object_id(override) == object_id_str
      end)

    updated_data_map = Map.put(data_map, :gallery_object_overrides, updated_overrides)
    Changeset.put_change(block_changeset, :data, updated_data_map)
  end

  # Extracts gallery overrides and a plain map from block data that may be a changeset,
  # a struct, or a plain map (from a previous put_change call).
  defp extract_gallery_data(%Ecto.Changeset{} = cs) do
    struct = Changeset.apply_changes(cs)
    {Map.get(struct, :gallery_object_overrides, []), Map.from_struct(struct)}
  end

  defp extract_gallery_data(data) when is_struct(data) do
    {Map.get(data, :gallery_object_overrides, []), Map.from_struct(data)}
  end

  defp extract_gallery_data(data) when is_map(data) do
    {Map.get(data, :gallery_object_overrides, []), data}
  end

  # Shared helpers for gallery media operations

  defp fetch_media(:image, id), do: Brando.Images.get_image(id)
  defp fetch_media(:video, id), do: Brando.Videos.get_video(%{matches: %{id: id}, preload: [:thumbnail]})

  defp media_id_field(:image), do: :image_id
  defp media_id_field(:video), do: :video_id

  defp media_assoc_field(:image), do: :image
  defp media_assoc_field(:video), do: :video

  defp put_media_fields(map, media_type, media_id, media) do
    Map.merge(map, %{
      media_id_field(media_type) => media_id,
      media_assoc_field(media_type) => media
    })
  end

  defp preserve_gallery_object(obj) do
    Map.take(obj, [:id, :image_id, :video_id, :gallery_id, :sequence, :creator_id])
    |> maybe_add_association(:image, obj)
    |> maybe_add_association(:video, obj)
  end

  defp get_override_object_id(override) do
    case override do
      %Changeset{} -> Changeset.get_field(override, :object_id)
      %{object_id: id} -> id
      _ -> nil
    end
  end
end
