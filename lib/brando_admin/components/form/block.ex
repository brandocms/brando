defmodule BrandoAdmin.Components.Form.Block do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext
  import Phoenix.LiveView.TagEngine
  import PolymorphicEmbed.HTML.Component
  alias Ecto.Changeset
  alias BrandoAdmin.Components.Content
  alias BrandoAdmin.Components.Form
  alias BrandoAdmin.Components.Form.BlockField
  alias BrandoAdmin.Components.Form.Input
  alias BrandoAdmin.Components.Form.Input.Blocks
  alias BrandoAdmin.Components.Form.Input.Entries
  alias BrandoAdmin.Components.Form.Input.RenderVar
  alias BrandoAdmin.Components.Form.Block.Events
  alias Brando.Content.BlockIdentifier
  alias Brando.Content.Var
  alias Brando.Villain

  def mount(socket) do
    socket
    |> assign(:block_initialized, false)
    |> assign(:container_not_found, false)
    |> assign(:module_not_found, false)
    |> assign(:entry_template, nil)
    |> assign(:initial_render, false)
    |> assign(:dom_id, nil)
    |> assign(:position_response_tracker, [])
    |> assign(:source, nil)
    |> assign(:live_preview_active?, false)
    |> assign(:live_preview_cache_key, nil)
    |> Events.attach_block_events()
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
    children = Ecto.Changeset.get_assoc(block_cs, :children, :struct)
    vars = Ecto.Changeset.get_assoc(block_cs, :vars, :struct)
    table_rows = Ecto.Changeset.get_assoc(block_cs, :table_rows, :struct)

    updated_block_cs =
      block_cs
      |> Map.put(:action, :insert)
      |> Changeset.apply_changes()
      |> Map.merge(%{
        id: nil,
        uid: new_uid,
        sequence: new_sequence,
        creator_id: current_user_id,
        children: [],
        vars: [],
        table_rows: []
      })
      |> Changeset.change()
      |> Villain.duplicate_vars(vars, current_user_id)
      |> Villain.duplicate_table_rows(table_rows)
      |> Villain.add_uid_to_refs()
      |> Changeset.update_change(:refs, fn ref_changesets ->
        Enum.reject(ref_changesets, &(&1.action == :replace))
      end)
      |> Villain.duplicate_children(children, current_user_id)

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
    |> stream_insert(:children_forms, block_form, at: new_sequence)
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
          parent_sequence: sequence
        )
      end

      {:ok, socket}
    else
      vars = Ecto.Changeset.get_assoc(block_cs, :vars, :struct)
      table_rows = Ecto.Changeset.get_assoc(block_cs, :table_rows, :struct)

      updated_block_cs =
        block_cs
        |> Map.put(:action, :insert)
        |> Changeset.apply_changes()
        |> Map.merge(%{
          id: nil,
          uid: new_uid,
          sequence: new_sequence,
          creator_id: current_user_id,
          children: [],
          vars: [],
          table_rows: []
        })
        |> Changeset.change()
        |> Villain.duplicate_vars(vars, current_user_id)
        |> Villain.duplicate_table_rows(table_rows)
        |> Villain.add_uid_to_refs()
        |> Changeset.update_change(:refs, fn ref_changesets ->
          Enum.reject(ref_changesets, &(&1.action == :replace))
        end)

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
      |> stream_insert(:children_forms, block_form, at: sequence)
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
        },
        socket
      ) do
    changeset = socket.assigns.form.source
    has_children? = socket.assigns.has_children?
    parent_cid = socket.assigns.parent_cid

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
          parent_sequence: parent_sequence
        )
      end

      {:ok, socket}
    else
      send_update(parent_cid, %{
        event: "provide_changeset_for_duplication",
        changeset: changeset,
        uid: uid,
        parent_uid: parent_uid,
        root_uid: root_uid,
        parent_sequence: parent_sequence
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
        },
        socket
      ) do
    changeset = socket.assigns.form.source
    changesets = socket.assigns.changesets
    updated_changesets = update_child_changeset(changesets, uid, child_changeset)
    this_uid = socket.assigns.uid
    parent_cid = socket.assigns.parent_cid

    if !Enum.any?(updated_changesets, &(elem(&1, 1) == nil)) do
      updated_changesets_list = Enum.map(updated_changesets, &elem(&1, 1))

      # if the changeset struct is a block we put it directly,
      # but if it's an entry block we need to put it under the block association
      updated_changeset =
        if changeset.data.__struct__ == Brando.Content.Block do
          Changeset.put_assoc(
            changeset,
            :children,
            Enum.map(updated_changesets_list, &Brando.Utils.set_action/1)
          )
        else
          updated_block_changeset =
            changeset
            |> Changeset.get_assoc(:block)
            |> Changeset.put_assoc(
              :children,
              Enum.map(updated_changesets_list, &Brando.Utils.set_action/1)
            )

          Changeset.put_assoc(changeset, :block, updated_block_changeset)
        end

      if root_uid == this_uid do
        # we have the changeset with child changesets, now we need to send it to the parent for duplication
        send_update(parent_cid, %{
          event: "duplicate_block",
          uid: root_uid,
          changeset: updated_changeset,
          populated: true
        })
      else
        send_update(parent_cid, %{
          event: "provide_changeset_for_duplication",
          changeset: updated_changeset,
          uid: this_uid,
          parent_uid: parent_uid,
          root_uid: root_uid,
          parent_sequence: parent_sequence
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
      for {block_uid, _} <- changesets do
        id = "#{id}-child-#{block_uid}"

        send_update(__MODULE__,
          id: id,
          event: "enable_live_preview",
          cache_key: cache_key
        )
      end
    end

    socket
    |> assign(:live_preview_active?, true)
    |> assign(:live_preview_cache_key, cache_key)
    |> then(&{:ok, &1})
  end

  def update(%{event: "disable_live_preview"}, socket) do
    has_children? = socket.assigns.has_children?
    changesets = socket.assigns.changesets
    id = socket.assigns.id

    if has_children? do
      for {block_uid, _} <- changesets do
        id = "#{id}-child-#{block_uid}"

        send_update(__MODULE__,
          id: id,
          event: "disable_live_preview"
        )
      end
    end

    socket
    |> assign(:live_preview_active?, false)
    |> assign(:live_preview_cache_key, nil)
    |> then(&{:ok, &1})
  end

  def update(%{event: "delete_block", uid: uid, dom_id: dom_id}, socket) do
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
    |> stream_delete_by_dom_id(:children_forms, dom_id)
    |> update(:block_count, &(&1 - 1))
    |> reset_position_response_tracker()
    |> send_child_position_update(new_block_list)
    |> update_live_preview_on_empty_block_list()
    |> then(&{:ok, &1})
  end

  def update(%{event: "update_sequence", sequence: sequence}, socket) do
    belongs_to = socket.assigns.belongs_to
    parent_cid = socket.assigns.parent_cid
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

    send_update(parent_cid, %{event: "signal_position_update", uid: uid})

    {:ok,
     socket
     |> assign(:form_has_changes, updated_form.source.changes !== %{})
     |> assign(:form, updated_form)}
  end

  def update(%{event: "signal_position_update", uid: uid}, socket) do
    form_cid = socket.assigns.form_cid
    position_response_tracker = socket.assigns.position_response_tracker

    position_response_tracker =
      Enum.map(position_response_tracker, fn
        {^uid, _} -> {uid, true}
        item -> item
      end)

    if Enum.any?(position_response_tracker, &(elem(&1, 1) == false)) do
      {:ok, assign(socket, :position_response_tracker, position_response_tracker)}
    else
      send_update(form_cid, %{event: "update_live_preview"})
      {:ok, assign(socket, :position_response_tracker, position_response_tracker)}
    end
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
    parent_cid = socket.assigns.parent_cid
    changeset = socket.assigns.form.source
    uid = socket.assigns.uid
    has_children? = socket.assigns.has_children?
    changesets = socket.assigns.changesets

    if socket.assigns.deleted do
      # if the block is deleted, we don't message the children.
      if tag == :save do
        send(self(), {:progress_popup, "Providing block #{uid}..."})
      end

      send_update(parent_cid, %{
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

        send_update(parent_cid, %{
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
    parent_cid = socket.assigns.parent_cid
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

      send_update(parent_cid, %{
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
    parent_cid = socket.assigns.parent_cid
    level = socket.assigns.level
    changeset = socket.assigns.form.source

    changesets = socket.assigns.changesets
    updated_changesets = update_child_changeset(changesets, uid, child_changeset)

    if !Enum.any?(updated_changesets, &(elem(&1, 1) == nil)) do
      updated_changesets_list = Enum.map(updated_changesets, &elem(&1, 1))

      # if the changeset struct is a block we put it directly,
      # but if it's an entry block we need to put it under the block association
      updated_changeset =
        if changeset.data.__struct__ == Brando.Content.Block do
          Changeset.put_assoc(
            changeset,
            :children,
            Enum.map(updated_changesets_list, &Brando.Utils.set_action/1)
          )
        else
          updated_block_changeset =
            changeset
            |> Changeset.get_assoc(:block)
            |> Changeset.put_assoc(
              :children,
              Enum.map(updated_changesets_list, &Brando.Utils.set_action/1)
            )

          Changeset.put_assoc(changeset, :block, updated_block_changeset)
        end

      if level == 0 do
        if tag == :save do
          send(self(), {:progress_popup, "Providing root block #{uid}..."})
        end

        send_update(parent_cid, %{
          event: "provide_root_block",
          changeset: updated_changeset,
          uid: parent_uid,
          tag: tag
        })
      else
        if tag == :save do
          send(self(), {:progress_popup, "Providing block #{uid}..."})
        end

        send_update(parent_cid, %{
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
    {:ok, stream_insert(socket, :children_forms, form)}
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
    |> stream_insert(:children_forms, block_form, at: sequence)
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
    refs = Ecto.Changeset.get_embed(block_changeset, :refs)

    new_refs =
      Enum.reduce(refs, [], fn
        %Changeset{action: :replace}, acc ->
          acc

        old_ref, acc ->
          if Changeset.get_field(old_ref, :name) == ref.name do
            acc ++ List.wrap(ref)
          else
            acc ++ List.wrap(old_ref)
          end
      end)

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_embed(block_changeset, :refs, new_refs)
        changeset = Changeset.put_assoc(changeset, :block, updated_block_changeset)
        render_and_update_entry_block_changeset(changeset, entry, has_vars?, has_table_rows?)
      else
        changeset = Changeset.put_embed(changeset, :refs, new_refs)
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
    # |> send_form_to_parent_stream()
    |> maybe_update_live_preview_block()
    |> then(&{:ok, &1})
  end

  def update(%{event: "update_ref_data", ref_name: ref_name, ref_data: ref_data}, socket) do
    form = socket.assigns.form
    changeset = form.source
    belongs_to = socket.assigns.belongs_to
    uid = socket.assigns.uid
    has_vars? = socket.assigns.has_vars?
    has_table_rows? = socket.assigns.has_table_rows?
    entry = socket.assigns.entry

    block_changeset = get_block_changeset(changeset, belongs_to)
    refs = Changeset.get_embed(block_changeset, :refs)

    new_refs =
      Enum.reduce(refs, [], fn
        %Changeset{action: :replace}, acc ->
          acc

        ref, acc ->
          if Changeset.get_field(ref, :name) == ref_name do
            block =
              ref
              |> Changeset.get_field(:data)
              |> Changeset.change()

            updated_block =
              Changeset.put_embed(block, :data, ref_data)

            acc ++ List.wrap(Changeset.force_change(ref, :data, updated_block))
          else
            acc ++ List.wrap(ref)
          end
      end)

    updated_changeset =
      if belongs_to == :root do
        block_changeset = Changeset.get_assoc(changeset, :block)
        updated_block_changeset = Changeset.put_embed(block_changeset, :refs, new_refs)
        changeset = Changeset.put_assoc(changeset, :block, updated_block_changeset)
        render_and_update_entry_block_changeset(changeset, entry, has_vars?, has_table_rows?)
      else
        changeset = Changeset.put_embed(changeset, :refs, new_refs)
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
    |> maybe_update_live_preview_block()
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
        Changeset.get_assoc(block_cs, :table_rows) != []
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
    loaded? = if is_list(vars), do: true, else: vars != nil

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
    form_cid = socket.assigns.form_cid
    cid = socket.assigns.myself
    send_update(form_cid, %{event: "get_live_preview_status", cid: cid})
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

  def register_block_wanting_entry(cid, form_cid) do
    send_update(form_cid, %{event: "register_block_wanting_entry", cid: cid})
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
        |> assign_new(:module_color, fn -> module.color end)
        |> assign_new(:is_datasource?, fn -> module.datasource end)
        |> assign_new(:has_table_template?, fn -> (module.table_template_id && true) || false end)
        |> assign_new(:table_template, fn ->
          table_template_id = module.table_template_id

          if table_template_id do
            {:ok, table_template} =
              Brando.Content.get_table_template(%{
                matches: %{id: table_template_id},
                preload: [:vars]
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
    cid = socket.assigns.myself
    form_cid = socket.assigns.form_cid

    register_block_wanting_entry(cid, form_cid)
    socket
  end

  def maybe_register_block_wanting_entry(%{assigns: %{block_initialized: false}} = socket) do
    # check if the module code contains any entry variables. these can be in for loops, if/unless,
    # assign statements, or in the module code itself
    module_code = socket.assigns.module_code

    if Regex.run(~r/entry\.[a-zA-Z0-9_]+/, module_code) do
      cid = socket.assigns.myself
      form_cid = socket.assigns.form_cid

      register_block_wanting_entry(cid, form_cid)
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

  def reset_position_response_tracker(socket) do
    block_list = socket.assigns.block_list
    assign(socket, :position_response_tracker, Enum.map(block_list, &{&1, false}))
  end

  # after we've sent messages to block asking for position updates, if we have deleted the
  # last child block, we refresh the live preview
  defp update_live_preview_on_empty_block_list(%{assigns: %{block_list: []}} = socket) do
    form_cid = socket.assigns.form_cid
    send_update(form_cid, %{event: "update_live_preview"})
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
        Map.get(entry, :language),
        socket.assigns.vars
      )

    assign(socket, :available_identifiers, available_identifiers)
  end

  # we don't touch the child form stream if the block is already initialized
  def maybe_assign_children(%{assigns: %{block_initialized: true}} = socket), do: socket

  def maybe_assign_children(%{assigns: %{children: []}} = socket) do
    socket
    |> assign_new(:block_list, fn -> [] end)
    |> assign_new(:changesets, fn -> [] end)
    |> assign_new(:block_count, fn -> 0 end)
    |> stream(:children_forms, [])
  end

  def maybe_assign_children(%{assigns: %{type: :container, children: children}} = socket) do
    current_user_id = socket.assigns.current_user_id

    children_forms =
      Enum.map(
        children,
        &to_change_form(&1, %{}, current_user_id)
      )

    socket
    |> stream(:children_forms, children_forms)
    |> assign_new(:block_count, fn -> Enum.count(children) end)
    |> assign_new(:changesets, fn -> Enum.map(children, &{extract_uid(&1), nil}) end)
    |> assign_new(:block_list, fn -> Enum.map(children, &extract_uid(&1)) end)
  end

  def maybe_assign_children(%{assigns: %{type: :module, multi: true, children: children}} = socket) do
    current_user_id = socket.assigns.current_user_id

    children_forms =
      Enum.map(
        children,
        &to_change_form(&1, %{}, current_user_id)
      )

    socket
    |> stream(:children_forms, children_forms)
    |> assign_new(:block_count, fn -> Enum.count(children) end)
    |> assign_new(:changesets, fn -> Enum.map(children, &{extract_uid(&1), nil}) end)
    |> assign_new(:block_list, fn -> Enum.map(children, &extract_uid(&1)) end)
  end

  def maybe_assign_children(socket) do
    socket
    |> assign_new(:block_count, fn -> 0 end)
    |> assign_new(:block_list, fn -> [] end)
    |> assign_new(:changesets, fn -> [] end)
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

  def update_child_changeset(changesets, uid, new_changeset) do
    Enum.map(changesets, fn
      {^uid, _changeset} -> {uid, new_changeset}
      {uid, changeset} -> {uid, changeset}
    end)
  end

  def insert_child_changeset(changesets, uid, position) do
    List.insert_at(changesets, position, {uid, nil})
  end

  def delete_child_changeset(changesets, uid) do
    Enum.reject(changesets, fn
      {^uid, _} -> true
      _ -> false
    end)
  end

  def render(%{module_not_found: true} = assigns) do
    ~H"""
    <div class="alert danger text-mono">
      <div>
        Missing module — #{inspect(assigns.module_id)}.<br /><br />
        If this is a mistake, you can hopefully undelete the module.<br /><br /> If you're sure the module is gone, you can
        <button type="button" phx-click="delete_block" phx-target={@myself}>
          delete this block.
        </button>
      </div>
    </div>
    """
  end

  def render(%{type: :module, multi: true} = assigns) do
    ~H"""
    <div data-module-multi="true">
      <.module
        form={@form}
        dirty={@form_has_changes}
        new={@form_is_new}
        level={@level}
        belongs_to={@belongs_to}
        deleted={@deleted}
        multi={true}
        is_datasource?={@is_datasource?}
        has_table_template?={@has_table_template?}
        table_template_name={@table_template_name}
        module_class={@module_class}
        module_color={@module_color}
        module_name={@module_name}
        block_module={@block_module}
        vars={@vars}
        liquid_splits={@liquid_splits}
        parent_uploads={@parent_uploads}
        target={@myself}
        insert_block={
          JS.push("insert_block", target: @myself)
          |> show_modal(@module_picker_id)
        }
        insert_multi_block={
          JS.push("insert_block_entry", value: %{multi: true}, target: @myself)
          |> show_modal(@module_picker_id)
        }
        insert_child_block={
          JS.push("insert_block", value: %{multi: true}, target: @myself)
          |> show_modal(@module_picker_id)
        }
        has_children?={@has_children?}
      >
        <div
          :if={@has_children?}
          id={"#{@id}-children"}
          class="block-children"
          phx-update="stream"
          phx-hook="Brando.SortableBlocks"
          data-sortable-id={"sortable-blocks-multi-#{@uid}"}
          data-sortable-handle=".sort-handle"
          data-sortable-selector=".block"
        >
          <div
            :for={{id, child_block_form} <- @streams.children_forms}
            id={id}
            data-id={child_block_form.data.id}
            data-uid={child_block_form[:uid].value}
            data-parent_id={child_block_form[:parent_id].value}
            data-parent_uid={@uid}
          >
            <.live_component
              module={__MODULE__}
              id={"#{@id}-child-#{child_block_form[:uid].value}"}
              dom_id={id}
              multi={child_block_form[:multi].value}
              block_module={@block_module}
              block_field={@block_field}
              children={child_block_form[:children].value}
              live_preview_active?={@live_preview_active?}
              live_preview_cache_key={@live_preview_cache_key}
              parent_cid={@myself}
              parent_uid={@uid}
              parent_path={@path}
              parent_uploads={@parent_uploads}
              parent_module_id={@module_id}
              module_set={@module_set}
              form={child_block_form}
              form_cid={@form_cid}
              entry={@entry}
              current_user_id={@current_user_id}
              belongs_to={:multi}
              level={@level + 1}
            />
          </div>
        </div>
      </.module>
    </div>
    """
  end

  def render(%{type: :module} = assigns) do
    ~H"""
    <div>
      <.module
        form={@form}
        dirty={@form_has_changes}
        new={@form_is_new}
        level={@level}
        belongs_to={@belongs_to}
        deleted={@deleted}
        parent_uploads={@parent_uploads}
        is_datasource?={@is_datasource?}
        has_table_template?={@has_table_template?}
        table_template_name={@table_template_name}
        target={@myself}
        module_class={@module_class}
        block_module={@block_module}
        vars={@vars}
        liquid_splits={@liquid_splits}
        insert_block={JS.push("insert_block", target: @myself) |> show_modal(@module_picker_id)}
        has_children?={false}
        module_name={@module_name}
        module_color={@module_color}
        module_datasource_module_label={@module_datasource_module_label}
        module_datasource_type={@module_datasource_type}
        module_datasource_query={@module_datasource_query}
        datasource_meta={@datasource_meta}
        available_identifiers={@available_identifiers}
      />
    </div>
    """
  end

  def render(%{type: :module_entry} = assigns) do
    ~H"""
    <div>
      <.module
        form={@form}
        dirty={@form_has_changes}
        new={@form_is_new}
        level={@level}
        belongs_to={@belongs_to}
        deleted={@deleted}
        parent_uploads={@parent_uploads}
        is_datasource?={@is_datasource?}
        has_table_template?={@has_table_template?}
        table_template_name={@table_template_name}
        target={@myself}
        module_class={@module_class}
        block_module={@block_module}
        vars={@vars}
        liquid_splits={@liquid_splits}
        insert_block={JS.push("insert_block_entry", target: @myself) |> show_modal(@module_picker_id)}
        has_children?={false}
        module_name={@module_name}
        module_color={@module_color}
      />
    </div>
    """
  end

  def render(%{type: :container} = assigns) do
    ~H"""
    <div>
      <.container
        form={@form}
        dirty={@form_has_changes}
        new={@form_is_new}
        level={@level}
        belongs_to={@belongs_to}
        block_module={@block_module}
        deleted={@deleted}
        target={@myself}
        palette_options={@palette_options}
        container={@container}
        containers={@containers}
        insert_block={
          JS.push("insert_block", target: @myself)
          |> show_modal(@module_picker_id)
        }
        insert_child_block={
          JS.push("insert_block", value: %{container: true}, target: @myself)
          |> show_modal(@module_picker_id)
        }
        has_children?={@has_children?}
      >
        <div
          :if={@has_children?}
          id={"#{@id}-children"}
          class="block-children"
          phx-update="stream"
          phx-hook="Brando.SortableBlocks"
          data-sortable-id="sortable-blocks"
          data-sortable-handle=".sort-handle"
          data-sortable-selector=".block"
        >
          <div
            :for={{id, child_block_form} <- @streams.children_forms}
            id={id}
            data-id={child_block_form[:id].value}
            data-uid={child_block_form[:uid].value}
            data-parent_id={child_block_form[:parent_id].value}
            data-parent_uid={@uid}
            class="draggable"
          >
            <.live_component
              module={__MODULE__}
              id={"#{@id}-child-#{child_block_form[:uid].value}"}
              dom_id={id}
              block_module={@block_module}
              block_field={@block_field}
              children={child_block_form[:children].value}
              live_preview_active?={@live_preview_active?}
              live_preview_cache_key={@live_preview_cache_key}
              parent_cid={@myself}
              parent_uid={@uid}
              parent_path={@path}
              parent_uploads={@parent_uploads}
              module_set={@module_set}
              entry={@entry}
              form={child_block_form}
              form_cid={@form_cid}
              current_user_id={@current_user_id}
              belongs_to={:container}
              level={@level + 1}
            >
            </.live_component>
          </div>
        </div>
      </.container>
    </div>
    """
  end

  def render(%{type: :fragment} = assigns) do
    ~H"""
    <div>
      <.fragment_block
        form={@form}
        dirty={@form_has_changes}
        new={@form_is_new}
        level={@level}
        fragment={@fragment}
        fragments={@fragments}
        belongs_to={@belongs_to}
        insert_block={JS.push("insert_block", target: @myself) |> show_modal(@module_picker_id)}
        deleted={@deleted}
        target={@myself}
        block_module={@block_module}
      />
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div style="font-family: Mono; font-size: 11px;">
      <code>
        <pre>
      ERROR: Unknown block type

      Assign keys:

      <%= inspect Map.keys(assigns), pretty: true, width: 0 %>

      - type: <%= inspect @type %>
      - multi: <%= inspect @multi %>
      </pre>
      </code>
    </div>
    """
  end

  ##
  ## Function components

  attr :form, :any
  attr :dirty, :any
  attr :new, :any
  attr :level, :any
  attr :belongs_to, :any
  attr :deleted, :any
  attr :target, :any
  attr :block_module, :any
  attr :insert_block, :any
  attr :fragment, :any, default: nil
  attr :fragments, :list, default: []

  def fragment_block(assigns) do
    changeset = assigns.form.source
    belongs_to = assigns.belongs_to
    block_cs = get_block_changeset(changeset, belongs_to)
    fragment_id = Changeset.get_field(block_cs, :fragment_id)

    assigns =
      assigns
      |> assign(:uid, Changeset.get_field(block_cs, :uid))
      |> assign(:type, Changeset.get_field(block_cs, :type))
      |> assign(:fragment_id, fragment_id)
      |> assign(:active, Changeset.get_field(block_cs, :active))
      |> assign(:collapsed, Changeset.get_field(block_cs, :collapsed))
      |> assign(
        :update_url,
        fragment_id && Brando.Pages.Fragment.__admin_route__(:update, [fragment_id])
      )

    ~H"""
    <div
      id={"base-block-#{@uid}"}
      data-block-uid={@uid}
      class={[
        "base-block",
        @collapsed && "collapsed",
        @active == false && "disabled",
        @deleted && "deleted",
        (@dirty or @new) && "dirty"
      ]}
    >
      <.plus click={@insert_block} />

      <div
        id={"block-#{@uid}"}
        data-block-uid={@uid}
        data-block-type={@type}
        data-fragment-id={@fragment_id}
        class={["block"]}
        phx-hook="Brando.Block"
      >
        <.form for={@form} phx-value-id={@form.data.id} phx-change="validate_block" phx-target={@target}>
          <%= if @belongs_to == :root do %>
            <Input.hidden field={@form[:sequence]} />
            <Input.hidden field={@form[:marked_as_deleted]} />
            <.inputs_for :let={block_form} field={@form[:block]}>
              <.hidden_block_fields block_form={block_form} block_module={@block_module} />
              <.toolbar
                uid={@uid}
                collapsed={@collapsed}
                type={@type}
                multi={false}
                config={true}
                block={block_form}
                target={@target}
                palette={nil}
                container={nil}
                is_ref?={false}
                is_datasource?={false}
                has_table_template?={false}
              >
                <:description>
                  <%= if @fragment do %>
                    [{@fragment.parent_key}/<strong><%= @fragment.key %></strong>] {@fragment.title} — {@fragment.language}
                  <% end %>
                </:description>
              </.toolbar>
              <.fragment_config uid={@uid} block={block_form} target={@target} fragment={@fragment} fragments={@fragments} />
              <div class="block-content">
                <div class="block-fragment-wrapper">
                  <div class="fragment-info" phx-click="show_fragment_instructions" phx-target={@target}>
                    <div class="icon">
                      <span class="hero-puzzle-piece"></span>
                    </div>
                    <div class="info">
                      <span class="fragment-label">
                        {gettext("Embedded")}<br /> {gettext("fragment")}
                      </span>
                    </div>
                  </div>

                  <div :if={!@fragment_id} class="block-instructions">
                    <p>
                      {gettext("This block embeds a fragment as a block, but no fragment is currently selected.")}
                    </p>
                    <button type="button" class="tiny" phx-click={show_modal("#block-#{@uid}_config")} phx-target={@target}>
                      {gettext("Add fragment")}
                    </button>
                  </div>
                  <div :if={@fragment} class="fragment-info">
                    <.link :if={@update_url} class="tiny button" href={@update_url} target="_blank">
                      {gettext("Edit fragment")}
                    </.link>
                  </div>
                </div>
              </div>
            </.inputs_for>
          <% else %>
            <section class="alert danger">
              {gettext("This block is currently not allowed to be a child block :(")}
            </section>
          <% end %>
        </.form>
      </div>
    </div>
    """
  end

  def container(assigns) do
    changeset = assigns.form.source
    belongs_to = assigns.belongs_to

    block_cs = get_block_changeset(changeset, belongs_to)
    palette = Changeset.get_assoc(block_cs, :palette, :struct)
    bg_color = extract_block_bg_color(palette)

    assigns =
      assigns
      |> assign(:uid, Changeset.get_field(block_cs, :uid))
      |> assign(:type, Changeset.get_field(block_cs, :type))
      |> assign(:container_id, Changeset.get_field(block_cs, :container_id))
      |> assign(:description, Changeset.get_field(block_cs, :description))
      |> assign(:active, Changeset.get_field(block_cs, :active))
      |> assign(:collapsed, Changeset.get_field(block_cs, :collapsed))
      |> assign(:palette, palette)
      |> assign(:bg_color, bg_color)

    ~H"""
    <div
      id={"base-block-#{@uid}"}
      data-block-uid={@uid}
      class={[
        "base-block",
        @collapsed && "collapsed",
        @active == false && "disabled",
        @deleted && "deleted",
        (@dirty or @new) && "dirty"
      ]}
    >
      <.plus click={@insert_block} />

      <div
        id={"block-#{@uid}"}
        data-block-uid={@uid}
        data-block-type={@type}
        data-container-id={@container_id}
        class="block"
        phx-hook="Brando.Block"
        style={"background-color: #{@bg_color}"}
      >
        <.form for={@form} phx-value-id={@form.data.id} phx-change="validate_block" phx-target={@target}>
          <%= if @belongs_to == :root do %>
            <Input.hidden field={@form[:sequence]} />
            <Input.hidden field={@form[:marked_as_deleted]} />
            <.inputs_for :let={block_form} field={@form[:block]}>
              <.hidden_block_fields block_form={block_form} block_module={@block_module} />
              <.toolbar
                uid={@uid}
                collapsed={@collapsed}
                type={@type}
                multi={false}
                config={true}
                block={block_form}
                target={@target}
                palette={@palette}
                container={@container}
                is_ref?={false}
                is_datasource?={false}
                has_table_template?={false}
                has_children?={@has_children?}
              />
              <.container_config
                uid={@uid}
                block={block_form}
                target={@target}
                palette={@palette}
                palette_options={@palette_options}
                container={@container}
                containers={@containers}
              />
            </.inputs_for>
          <% else %>
            <section class="alert danger">
              {gettext("This block is currently not allowed to be a child block :(")}
            </section>
          <% end %>
        </.form>
        <%= if @has_children? do %>
          {render_slot(@inner_block)}
          <.plus click={@insert_child_block} />
        <% else %>
          <div class="blocks-empty-instructions">
            {gettext("Click the plus to start adding content blocks")}
          </div>
          <.plus click={@insert_child_block} />
        <% end %>
      </div>
    </div>
    """
  end

  attr :form, Phoenix.HTML.Form
  attr :dirty, :boolean, default: false
  attr :new, :boolean, default: false
  attr :level, :integer
  attr :belongs_to, :atom
  attr :deleted, :boolean, default: false
  attr :is_datasource?, :boolean, default: false
  attr :has_table_template?, :boolean, default: false
  attr :table_template_name, :string
  attr :module_class, :string, default: nil
  attr :block_module, :atom
  attr :vars, :list, default: []
  attr :parent_uploads, :list, default: []
  attr :target, :any
  attr :has_children?, :boolean, default: false
  attr :multi, :boolean, default: false
  attr :liquid_splits, :any, default: []
  attr :insert_block, :any, default: nil
  attr :insert_child_block, :any, default: nil
  attr :insert_multi_block, :any, default: nil
  attr :module_name, :string, default: nil
  attr :module_color, :string, default: nil
  attr :module_datasource_module_label, :string, default: ""
  attr :module_datasource_type, :string, default: ""
  attr :module_datasource_query, :string, default: ""
  attr :datasource_meta, :any, default: nil
  attr :available_identifiers, :any, default: []
  slot :inner_block

  def module(assigns) do
    changeset = assigns.form.source
    belongs_to = assigns.belongs_to
    block_cs = get_block_changeset(changeset, belongs_to)

    assigns =
      assigns
      |> assign(:uid, Changeset.get_field(block_cs, :uid))
      |> assign(:type, Changeset.get_field(block_cs, :type))
      |> assign(:module_id, Changeset.get_field(block_cs, :module_id))
      |> assign(:description, Changeset.get_field(block_cs, :description))
      |> assign(:active, Changeset.get_field(block_cs, :active))
      |> assign(:collapsed, Changeset.get_field(block_cs, :collapsed))

    ~H"""
    <div
      id={"base-block-#{@uid}"}
      data-block-uid={@uid}
      class={[
        "base-block",
        @collapsed && "collapsed",
        @active == false && "disabled",
        @deleted && "deleted",
        (@dirty or @new) && "dirty"
      ]}
    >
      <.plus click={@insert_block} />

      <div
        id={"block-#{@uid}"}
        data-block-uid={@uid}
        data-block-type={@type}
        data-module-id={@module_id}
        data-color={@module_color}
        class="block"
        phx-hook="Brando.Block"
      >
        <.form for={@form} phx-value-id={@form.data.id} phx-change="validate_block" phx-target={@target}>
          <%= if @belongs_to == :root do %>
            <Input.hidden field={@form[:sequence]} />
            <Input.hidden field={@form[:marked_as_deleted]} />
            <.inputs_for :let={block_form} field={@form[:block]}>
              <.hidden_block_fields block_form={block_form} block_module={@block_module} />
              <.toolbar
                uid={@uid}
                collapsed={@collapsed}
                type={@type}
                multi={@multi}
                config={true}
                block={block_form}
                target={@target}
                is_ref?={false}
                is_datasource?={@is_datasource?}
                has_children?={@has_children?}
              >
                <:description>
                  <.i18n map={@module_name} />
                </:description>
              </.toolbar>

              <.module_config uid={@uid} block_form={block_form} target={@target} />
              <.module_content
                uid={@uid}
                block_form={block_form}
                liquid_splits={@liquid_splits}
                module_class={@module_class}
                parent_uploads={@parent_uploads}
                has_table_template?={@has_table_template?}
                table_template_name={@table_template_name}
                target={@target}
                is_datasource?={@is_datasource?}
                datasource_meta={@datasource_meta}
                module_datasource_module_label={@module_datasource_module_label}
                module_datasource_type={@module_datasource_type}
                module_datasource_query={@module_datasource_query}
                available_identifiers={@available_identifiers}
                block_identifiers={block_form[:block_identifiers]}
              />
            </.inputs_for>
          <% else %>
            <Input.hidden field={@form[:sequence]} />
            <input type="hidden" name={@form[:id].name} value={@form[:id].value} />
            <.hidden_block_fields block_form={@form} block_module={@block_module} />

            <.toolbar
              uid={@uid}
              collapsed={@collapsed}
              config={true}
              type={@type}
              block={@form}
              target={@target}
              is_ref?={false}
              is_datasource?={@is_datasource?}
              has_children?={@has_children?}
            >
              <:description>
                <.i18n map={@module_name} />
              </:description>
            </.toolbar>

            <.module_config uid={@uid} block_form={@form} target={@target} />
            <.module_content
              uid={@uid}
              block_form={@form}
              liquid_splits={@liquid_splits}
              module_class={@module_class}
              has_table_template?={@has_table_template?}
              table_template_name={@table_template_name}
              parent_uploads={@parent_uploads}
              target={@target}
              is_datasource?={@is_datasource?}
              datasource_meta={@datasource_meta}
              module_datasource_module_label={@module_datasource_module_label}
              module_datasource_type={@module_datasource_type}
              module_datasource_query={@module_datasource_query}
              available_identifiers={@available_identifiers}
              block_identifiers={@form[:block_identifiers]}
            />
          <% end %>
        </.form>
        <%= if @has_children? do %>
          {render_slot(@inner_block)}
          <.plus click={@insert_multi_block} />
        <% else %>
          <%= if @multi do %>
            <div class="blocks-empty-instructions">
              {gettext("Click the plus to start adding content blocks")}
            </div>
            <.plus click={@insert_multi_block} />
          <% end %>
        <% end %>
      </div>
    </div>
    """
  end

  def module_content(assigns) do
    ~H"""
    <div class="block-content">
      <div b-editor-tpl={@module_class}>
        <.vars vars={@block_form[:vars]} uid={@uid} target={@target} />
        <.datasource
          :if={@is_datasource?}
          block_data={@block_form}
          uid={@uid}
          datasource_meta={@datasource_meta}
          module_datasource_module_label={@module_datasource_module_label}
          module_datasource_type={@module_datasource_type}
          module_datasource_query={@module_datasource_query}
          available_identifiers={@available_identifiers}
          block_identifiers={@block_identifiers}
          target={@target}
        />
        <div :if={@has_table_template?} class="block-table" id={"block-#{@uid}-block-table"}>
          <.table block_data={@block_form} uid={@uid} target={@target} table_template_name={@table_template_name} />
        </div>
        <div class="block-splits">
          <%= for split <- @liquid_splits do %>
            <%= case split do %>
              <% {:ref, ref} -> %>
                <.ref parent_uploads={@parent_uploads} refs_field={@block_form[:refs]} ref_name={ref} target={@target} />
              <% {:content, _} -> %>
                <div class="split_content"></div>
              <% {:entry_variable, var_name, variable_value} -> %>
                <div
                  phx-no-format
                  class="rendered-variable"
                  data-popover={
                    gettext("Edit the entry directly to affect this variable [entry.%{var_name}]",
                      var_name: var_name
                    )
                  }
                ><%= variable_value %></div>
              <% {:module_variable, var_name, variable_value} -> %>
                <div
                  phx-no-format
                  class="rendered-variable"
                  data-popover={
                    gettext("Edit the module variable to affect this variable [%{var_name}]",
                      var_name: var_name
                    )
                  }
                ><%= variable_value %></div>
              <% {:entry_picture, _, img_src} -> %>
                <figure>
                  <img src={img_src} />
                </figure>
              <% {:module_picture, _, img_src} -> %>
                <figure>
                  <img src={img_src} />
                </figure>
              <% _ -> %>
                {raw(split)}
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  def hidden_block_fields(assigns) do
    ~H"""
    <div class="hidden-block-fields">
      <Input.hidden field={@block_form[:uid]} />
      <Input.hidden field={@block_form[:type]} />
      <Input.hidden field={@block_form[:anchor]} />
      <Input.hidden field={@block_form[:multi]} />
      <Input.hidden field={@block_form[:module_id]} />
      <Input.hidden field={@block_form[:parent_id]} />
      <Input.hidden field={@block_form[:creator_id]} />
      <Input.hidden field={@block_form[:marked_as_deleted]} />
      <Input.input type={:hidden} field={@block_form[:source]} value={@block_module} />
    </div>
    """
  end

  attr :uid, :string, required: true
  attr :block_form, :any, required: true
  attr :target, :any, required: true

  def module_config(assigns) do
    ~H"""
    <Content.modal title={gettext("Configure")} id={"block-#{@uid}_config"} wide={true}>
      <div class="panels">
        <div class="panel">
          <Input.text
            field={@block_form[:description]}
            label={gettext("Block description")}
            instructions={gettext("Helpful for collapsed blocks")}
          />
          <Input.text field={@block_form[:anchor]} instructions={gettext("Anchor available to block.")} />
          <.vars vars={@block_form[:vars]} uid={@uid} important={false} target={@target} />
          <div>
            UID: <span class="text-mono">{@uid}</span>
          </div>
        </div>
        <div class="panel">
          <h2 class="titlecase">Vars</h2>
          <.inputs_for :let={var} field={@block_form[:vars]}>
            <div class="var">
              <div class="key">{var[:key].value}</div>
              <div class="buttons">
                <button
                  type="button"
                  class="tiny"
                  phx-click={JS.push("reset_var", target: @target)}
                  phx-value-id={var[:key].value}
                >
                  {gettext("Reset")}
                </button>
                <button
                  type="button"
                  class="tiny"
                  phx-click={JS.push("delete_var", target: @target)}
                  phx-value-id={var[:key].value}
                >
                  {gettext("Delete")}
                </button>
              </div>
            </div>
          </.inputs_for>

          <h2 class="titlecase">Refs</h2>
          <.inputs_for :let={ref} field={@block_form[:refs]}>
            <div class="ref">
              <div class="key">{ref[:name].value}</div>
              <button
                type="button"
                class="tiny"
                phx-click={JS.push("reset_ref", target: @target)}
                phx-value-id={ref[:name].value}
              >
                {gettext("Reset")}
              </button>
            </div>
          </.inputs_for>
          <h2 class="titlecase">{gettext("Advanced")}</h2>
          <div class="button-group-vertical">
            <button type="button" class="secondary" phx-click={JS.push("fetch_missing_refs", target: @target)}>
              {gettext("Fetch missing refs")}
            </button>
            <button type="button" class="secondary" phx-click={JS.push("reset_refs", target: @target)}>
              {gettext("Reset all block refs")}
            </button>
            <button type="button" class="secondary" phx-click={JS.push("fetch_missing_vars", target: @target)}>
              {gettext("Fetch missing vars")}
            </button>
            <button type="button" class="secondary" phx-click={JS.push("reset_vars", target: @target)}>
              {gettext("Reset all variables")}
            </button>
          </div>
        </div>
      </div>
      <:footer>
        <button type="button" class="primary" phx-click={hide_modal("#block-#{@uid}_config")}>
          {gettext("Close")}
        </button>
      </:footer>
    </Content.modal>
    """
  end

  attr :uid, :string, required: true
  attr :block, :any, required: true
  attr :fragment, :any, default: nil
  attr :fragments, :list, default: []
  attr :target, :any, required: true

  def fragment_config(assigns) do
    ~H"""
    <Content.modal title={gettext("Configure")} id={"block-#{@uid}_config"} wide={true}>
      <div class="panels">
        <div class="panel">
          <.live_component
            module={Input.Select}
            id={"#{@block.id}-fragment-select"}
            field={@block[:fragment_id]}
            label={gettext("Fragment")}
            opts={[options: @fragments]}
            publish
          />
          <Input.text field={@block[:anchor]} />
          <Input.text
            field={@block[:description]}
            label={gettext("Block description")}
            instructions={gettext("Helpful for collapsed blocks")}
          />
        </div>
      </div>
      <:footer>
        <button type="button" class="primary" phx-click={hide_modal("#block-#{@uid}_config")}>
          {gettext("Close")}
        </button>
      </:footer>
    </Content.modal>
    """
  end

  attr :uid, :string, required: true
  attr :block, :any, required: true
  attr :palette, :any, required: true
  attr :container, :any, default: nil
  attr :containers, :list, default: []
  attr :palette_options, :any, default: []
  attr :target, :any, required: true

  def container_config(assigns) do
    ~H"""
    <Content.modal title={gettext("Configure")} id={"block-#{@uid}_config"} wide={true}>
      <div class="panels">
        <div class="panel">
          <.live_component
            module={Input.Select}
            id={"#{@block.id}-container-select"}
            field={@block[:container_id]}
            label={gettext("Container template")}
            opts={[options: @containers, resetable: true]}
            publish
          />
          <%= if @palette_options do %>
            <.live_component
              module={Input.Select}
              id={"#{@block.id}-palette-select"}
              field={@block[:palette_id]}
              label={gettext("Palette")}
              opts={[options: @palette_options]}
              publish
            />
          <% else %>
            <Input.hidden field={@block[:palette_id]} />
          <% end %>
          <Input.text field={@block[:anchor]} />
          <Input.text
            field={@block[:description]}
            label={gettext("Block description")}
            instructions={gettext("Helpful for collapsed blocks")}
          />
        </div>
      </div>
      <:footer>
        <button type="button" class="primary" phx-click={hide_modal("#block-#{@uid}_config")}>
          {gettext("Close")}
        </button>
      </:footer>
    </Content.modal>
    """
  end

  attr :ref_name, :string, required: true
  attr :refs_field, :any, required: true
  attr :parent_uploads, :any, required: true
  attr :target, :any, required: true

  def ref(assigns) do
    refs = Changeset.get_embed(assigns.refs_field.form.source, :refs, :struct)
    ref_names = Enum.map(refs, & &1.name)
    ref_found = Enum.member?(ref_names, assigns.ref_name)

    assigns =
      assigns
      |> assign(:ref_found, ref_found)
      |> assign(:ref_names, ref_names)

    ~H"""
    <%= if @ref_found do %>
      <.inputs_for :let={ref_form} field={@refs_field} skip_hidden>
        <%= if ref_form[:name].value == @ref_name do %>
          <section b-ref={ref_form[:name].value}>
            <.polymorphic_embed_inputs_for :let={block} field={ref_form[:data]}>
              <.dynamic_block
                id={block[:uid].value}
                block_id={block[:uid].value}
                is_ref?={true}
                ref_name={ref_form[:name].value}
                ref_description={ref_form[:description].value}
                block={block}
                parent_uploads={@parent_uploads}
                target={@target}
              />
            </.polymorphic_embed_inputs_for>
            <Input.input type={:hidden} field={ref_form[:description]} />
            <Input.input type={:hidden} field={ref_form[:name]} />
            <Input.input type={:hidden} field={ref_form[:id]} />
          </section>
        <% end %>
      </.inputs_for>
    <% else %>
      <section class="alert danger">
        Ref <code>{@ref_name}</code>
        is missing!<br /><br /> If the module has been changed, this block might be out of sync!<br /><br />
        Available refs are:<br /><br />
        <div :for={ref_name <- @ref_names}>
          &rarr; {ref_name}<br />
        </div>
      </section>
    <% end %>
    """
  end

  def handle(assigns) do
    ~H"""
    <div class="sort-handle block-action" data-sortable-group={1} data-popover={gettext("Reposition block (click&drag)")}>
      <.icon name="hero-arrows-up-down" />
    </div>
    """
  end

  def dynamic_block(assigns) do
    assigns =
      assigns
      |> assign_new(:insert_module, fn -> nil end)
      |> assign_new(:duplicate_block, fn -> nil end)
      |> assign_new(:belongs_to, fn -> nil end)
      |> assign_new(:is_ref?, fn -> false end)
      |> assign_new(:opts, fn -> [] end)
      |> assign_new(:ref_name, fn -> nil end)
      |> assign_new(:ref_description, fn -> nil end)
      |> assign_new(:block_id, fn -> assigns.block[:uid].value end)
      |> assign_new(:component_target, fn ->
        type_atom = String.to_existing_atom(assigns.block[:type].value)

        block_type =
          (type_atom
           |> to_string()
           |> Macro.camelize()) <> "Block"

        block_module = Module.concat([Blocks, block_type])

        case Code.ensure_compiled(block_module) do
          {:module, _} -> block_module
          _ -> Function.capture(__MODULE__, type_atom, 1)
        end
      end)

    assigns =
      if is_nil(assigns.block_id) do
        random_id = Brando.Utils.generate_uid()

        block =
          put_in(
            assigns.block,
            [Access.key(:source), Access.key(:data), Access.key(:uid)],
            random_id
          )

        assigns
        |> assign(:block_id, random_id)
        |> assign(:block, block)
      else
        assigns
      end

    ~H"""
    <%= if is_function(@component_target) do %>
      {component(
        @component_target,
        assigns,
        {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
      )}
    <% else %>
      <.live_component
        module={@component_target}
        id={@block_id}
        block={@block}
        is_ref?={@is_ref?}
        opts={@opts}
        belongs_to={@belongs_to}
        ref_name={@ref_name}
        ref_description={@ref_description}
        insert_module={@insert_module}
        duplicate_block={@duplicate_block}
        parent_uploads={@parent_uploads}
        target={@target}
      />
    <% end %>
    """
  end

  attr :id, :string, required: true
  attr :target, :any, required: true
  attr :block, :any, required: true
  attr :multi, :boolean, default: false
  attr :wide_config, :boolean, default: false
  attr :type, :any
  attr :block_type, :any
  attr :is_datasource?, :boolean, default: false
  attr :is_ref?, :boolean, default: false
  attr :datasource, :any
  attr :bg_color, :string, default: nil
  attr :uid, :any

  slot :inner_block
  slot :config
  slot :config_footer
  slot :description
  slot :instructions

  def block(assigns) do
    block_cs = assigns.block.source
    uid = Changeset.get_field(block_cs, :uid) || Brando.Utils.generate_uid()

    assigns =
      assigns
      |> assign_new(:block_type, fn ->
        Changeset.get_field(block_cs, :type) || (assigns.is_entry? && "entry")
      end)
      |> assign(:uid, uid)
      |> assign(:active, Changeset.get_field(block_cs, :active))
      |> assign(:collapsed, Changeset.get_field(block_cs, :collapsed))
      |> assign(:marked_as_deleted, Changeset.get_field(block_cs, :marked_as_deleted))

    ~H"""
    <div
      id={"base-block-#{@uid}"}
      data-block-uid={@uid}
      class={[
        "base-block",
        "ref-block",
        @block_type,
        @collapsed && "collapsed",
        !@active && "disabled"
      ]}
    >
      <Content.modal title={gettext("Configure")} id={"block-#{@uid}_config"} wide={@wide_config}>
        <%= if @config do %>
          {render_slot(@config)}
        <% end %>
        <:footer>
          <button type="button" class="primary" phx-click={hide_modal("#block-#{@uid}_config")}>
            {gettext("Close")}
          </button>
          <%= if @config_footer do %>
            {render_slot(@config_footer)}
          <% end %>
        </:footer>
      </Content.modal>

      <Input.input type={:hidden} field={@block[:uid]} />

      <div
        id={"block-#{@uid}"}
        data-block-uid={@uid}
        data-block-type={@block_type}
        style={"background-color: #{@bg_color}"}
        class={["block", "ref_block"]}
        phx-hook="Brando.Block"
      >
        <.toolbar
          uid={@uid}
          collapsed={@collapsed}
          config={@config}
          type={@block_type}
          block={@block}
          target={@target}
          multi={@multi}
          is_ref?={@is_ref?}
          is_datasource?={false}
        >
          <:description>
            {render_slot(@description)}
          </:description>
        </.toolbar>

        <div class="block-content" id={"block-#{@uid}-block-content"}>
          {render_slot(@inner_block)}
        </div>
      </div>
    </div>
    """
  end

  ##
  ## Ref blocks

  def html(assigns) do
    assigns = assign(assigns, :uid, assigns.block[:uid].value)

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} multi={false} target={@target}>
          <:description>
            <%= if @ref_description not in ["", nil] do %>
              {@ref_description}
            <% end %>
          </:description>
          <div class="html-block">
            <Input.code field={block_data[:text]} label={gettext("Text")} />
          </div>
        </.block>
      </.inputs_for>
    </div>
    """
  end

  def markdown(assigns) do
    assigns = assign(assigns, :uid, assigns.block[:uid].value)

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} multi={false} target={@target}>
          <:description>
            <%= if @ref_description not in ["", nil] do %>
              {@ref_description}
            <% end %>
          </:description>
          <div class="markdown-block">
            <Input.code field={block_data[:text]} label={gettext("Text")} />
          </div>
        </.block>
      </.inputs_for>
    </div>
    """
  end

  def comment(assigns) do
    block_data_cs = get_block_data_changeset(assigns.block)

    assigns =
      assigns
      |> assign(:uid, assigns.block[:uid].value)
      |> assign(:text, Changeset.get_field(block_data_cs, :text))

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} multi={false} target={@target}>
          <:description>
            {gettext("Comment — not shown on frontend.")}
          </:description>
          <:config>
            <div id={"block-#{@uid}-conf-textarea"}>
              <Input.textarea field={block_data[:text]} />
            </div>
          </:config>
          <div id={"block-#{@uid}-comment"}>
            <%= if @text do %>
              {@text |> raw()}
            <% end %>
          </div>
        </.block>
      </.inputs_for>
    </div>
    """
  end

  def input(assigns) do
    assigns = assign(assigns, :uid, assigns.block[:uid].value)

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} multi={false} target={@target}>
          <:description>
            <%= if @ref_description not in ["", nil] do %>
              {@ref_description}
            <% end %>
          </:description>
          <div class="alert">
            <Input.text
              field={block_data[:value]}
              label={block_data[:label].value}
              instructions={block_data[:help_text].value}
              placeholder={block_data[:placeholder].value}
            />
            <Input.hidden field={block_data[:placeholder]} />
            <Input.hidden field={block_data[:label]} />
            <Input.hidden field={block_data[:type]} />
            <Input.hidden field={block_data[:help_text]} />
          </div>
        </.block>
      </.inputs_for>
    </div>
    """
  end

  def header(assigns) do
    assigns = assign(assigns, :uid, assigns.block[:uid].value)

    ~H"""
    <div id={"block-#{@uid}-wrapper"} data-block-uid={@uid}>
      <.inputs_for :let={block_data} field={@block[:data]}>
        <.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} multi={false} target={@target}>
          <:description>
            (H{block_data[:level].value})<%= if @ref_description do %>
              {@ref_description}
            <% end %>
          </:description>
          <:config>
            <Input.radios
              field={block_data[:level]}
              label="Level"
              uid={@uid}
              id_prefix="block_data"
              id={"block-#{@uid}-data-level"}
              opts={[
                options: [
                  %{label: "H1", value: 1},
                  %{label: "H2", value: 2},
                  %{label: "H3", value: 3},
                  %{label: "H4", value: 4},
                  %{label: "H5", value: 5},
                  %{label: "H6", value: 6}
                ]
              ]}
            />
            <Input.text field={block_data[:id]} label="ID" />
            <Input.text field={block_data[:link]} label="Link" />
          </:config>
          <div class="header-block">
            <Input.input
              type={:textarea}
              field={block_data[:text]}
              class={"h#{block_data[:level].value}"}
              phx-debounce={300}
              data-autosize={true}
              phx-update="ignore"
              rows={1}
            />
            <Input.input type={:hidden} field={block_data[:class]} />
            <Input.input type={:hidden} field={block_data[:placeholder]} />
          </div>
        </.block>
      </.inputs_for>
    </div>
    """
  end

  def text(assigns) do
    block_data_cs = get_block_data_changeset(assigns.block)

    extensions =
      case Changeset.get_field(block_data_cs, :extensions) do
        nil -> "all"
        extensions when is_list(extensions) -> Enum.join(extensions, "|")
        extensions -> extensions
      end

    assigns =
      assigns
      |> assign(:uid, assigns.block[:uid].value)
      |> assign(:text_type, Changeset.get_field(block_data_cs, :type))
      |> assign(:extensions, extensions)

    ~H"""
    <.inputs_for :let={text_block_data} field={@block[:data]}>
      <div id={"ref-#{@uid}-wrapper"} data-block-uid={@uid}>
        <.block id={"block-#{@uid}-base"} block={@block} is_ref?={true} multi={false} target={@target}>
          <:description>
            <%= if @ref_description not in [nil, ""] do %>
              {@ref_description}
            <% else %>
              {@text_type}
            <% end %>
          </:description>
          <:config>
            <Input.radios
              field={text_block_data[:type]}
              label="Type"
              opts={[
                options: [
                  %{label: "Paragraph", value: "paragraph"},
                  %{label: "Lede", value: "lede"}
                ]
              ]}
            />
            <%= if @extensions == "all" do %>
              <Input.hidden field={text_block_data[:extensions]} />
            <% else %>
              <Form.array_inputs :let={%{value: array_value, name: array_name}} field={text_block_data[:extensions]}>
                <input type="hidden" name={array_name} value={array_value} />
              </Form.array_inputs>
            <% end %>
          </:config>
          <div class={["text-block", @text_type]}>
            <div class="tiptap-wrapper" id={"block-#{@uid}-rich-text-wrapper"}>
              <div
                id={"block-#{@uid}-rich-text"}
                data-block-uid={@uid}
                data-tiptap-extensions={@extensions}
                phx-hook="Brando.TipTap"
                data-tiptap-type="block"
                data-name="TipTap"
              >
                <div id={"block-#{@uid}-rich-text-target-wrapper"} class="tiptap-target-wrapper" phx-update="ignore">
                  <div id={"block-#{@uid}-rich-text-target"} class="tiptap-target"></div>
                </div>
                <Input.input type={:hidden} field={text_block_data[:text]} class="tiptap-text" phx-debounce={400} />
              </div>
            </div>
          </div>
        </.block>
      </div>
    </.inputs_for>
    """
  end

  attr :click, :any, required: true

  def plus(assigns) do
    ~H"""
    <button class="block-plus" type="button" phx-click={@click}>
      <.icon name="hero-plus" />
    </button>
    """
  end

  attr :uid, :string, required: true
  attr :vars, :any, required: true
  attr :important, :boolean, default: true
  attr :target, :any

  def vars(assigns) do
    changeset = assigns.vars.form.source

    vars_to_render =
      changeset
      |> Changeset.get_assoc(:vars)
      |> Enum.filter(&(Changeset.get_field(&1, :important) == assigns.important))

    assigns = assign(assigns, :vars_to_render, vars_to_render)

    ~H"""
    <div :if={@vars_to_render != []} class="block-vars-wrapper">
      <div class="vars-info" phx-click="show_vars_instructions" phx-target={@target}>
        <div class="icon">
          <span class="hero-variable-mini"></span>
        </div>
        <div class="info">
          <span class="vars-label">
            {gettext("Block")}<br /> {gettext("Variables")}
          </span>
        </div>
      </div>
      <div class="block-vars">
        <.inputs_for :let={var} field={@vars} skip_hidden>
          <.live_component
            module={RenderVar}
            id={"block-#{@uid}-render-var-#{@important && "important" || "regular"}-#{var.id}"}
            var={var}
            render={(@important && :only_important) || :only_regular}
            on_change={fn params -> send_update(@target, params) end}
            publish
          >
            <input type="hidden" name={var[:id].name} value={var[:id].value} />
            <input type="hidden" name={var[:_persistent_id].name} value={var.index} />
          </.live_component>
        </.inputs_for>
      </div>
    </div>
    """
  end

  attr :uid, :string, required: true
  attr :collapsed, :boolean, default: false
  attr :type, :string
  attr :block, Phoenix.HTML.Form, required: true
  attr :target, :any, required: true
  attr :has_table_template?, :boolean, default: false
  attr :has_children?, :boolean, default: false
  attr :is_datasource?, :boolean, default: false
  attr :instructions, :string, default: nil
  attr :config, :boolean, default: false
  attr :multi, :boolean, default: false
  attr :is_ref?, :boolean, default: false
  attr :palette, :any, default: nil
  attr :container, :any, default: nil
  attr :module_datasource_module_label, :string, default: nil
  attr :module_datasource_type, :any, default: nil
  attr :module_datasource_query, :any, default: nil
  attr :available_identifiers, :list, default: []

  slot :inner_block
  slot :description

  def toolbar(assigns) do
    ~H"""
    <div class="block-toolbar">
      <div class="block-description">
        <Form.label field={@block[:active]} class="switch small inverse">
          <Input.input type={:checkbox} field={@block[:active]} />
          <div class="slider round"></div>
        </Form.label>
        <span class="block-type">
          <span :if={@is_datasource?} class="datasource">
            {gettext("Datamodule")} |
          </span>
          <span :if={@type == :module and not @is_datasource?} phx-no-format>
            <%= if @multi do %>Multi <% end %><%= gettext("Module") %> |
          </span>
          <span :if={@type == :module_entry}>
            {gettext("Entry")} |
          </span>
          <span :if={@type == :container}>
            {gettext("Container")} |
          </span>
          <span :if={@type == :fragment}>
            {gettext("Fragment")} |
          </span>
        </span>
        <span :if={@description} class="block-name">
          {render_slot(@description)}<span :if={@block[:active].value in [false, "false"]}> &lt;{gettext("Deactivated")}&gt;</span>
        </span>
        <%= if @type == :container do %>
          <%= if @container do %>
            {@container.name}
          <% else %>
            Standard
          <% end %>
          <%= if @palette do %>
            <div class="arrow">&rarr;</div>
            <button type="button" class="btn-palette" phx-click={show_modal("#block-#{@uid}_config")}>
              {@palette.name}
            </button>
            <div class="circle-stack">
              <span
                :for={color <- Enum.reverse(@palette.colors)}
                class="circle tiny"
                style={"background-color:#{color.hex_value}"}
                data-popover={"#{color.name}"}
              >
              </span>
            </div>
            <div :if={@block[:anchor].value} class="container-target">
              &nbsp;|&nbsp;#{@block[:anchor].value}
            </div>
          <% else %>
            <div class="arrow">&rarr;</div>
            <button type="button" class="btn-palette" phx-click={show_modal("#block-#{@uid}_config")}>
              {gettext("<No palette>")}
            </button>
          <% end %>
          <span :if={@block[:description].value not in ["", nil]} class="description">
            {@block[:description].value}
          </span>
        <% else %>
          <span :if={@block[:description].value not in ["", nil]} class="description">
            {@block[:description].value}
          </span>
        <% end %>
      </div>
      <div class="block-content" id={"block-#{@uid}-block-toolbar-content"}>
        {render_slot(@inner_block)}
      </div>
      <div class="block-actions" id={"block-#{@uid}-block-toolbar-actions"}>
        <.handle :if={!@is_ref?} />
        <div
          :if={@instructions}
          class="block-action help"
          phx-click={JS.push("toggle_help", target: @target)}
          data-popover={gettext("Show instructions")}
        >
          <.icon name="hero-question-mark-circle" />
        </div>
        <button
          :if={@is_ref? == false}
          type="button"
          phx-value-block_uid={@uid}
          class="block-action duplicate"
          phx-click="duplicate_block"
          phx-target={@target}
          data-popover={gettext("Duplicate block")}
        >
          <.icon name="hero-document-duplicate" />
        </button>
        <button
          :if={@config}
          type="button"
          class="block-action config"
          phx-click={show_modal("#block-#{@uid}_config")}
          data-popover={gettext("Configure block")}
        >
          <.icon name="hero-cog-8-tooth" />
        </button>
        <button
          :if={@is_ref? == false}
          type="button"
          class="block-action toggler"
          phx-click="delete_block"
          phx-target={@target}
          data-popover={gettext("Delete block")}
        >
          <.icon name="hero-trash" />
        </button>
        <Form.label
          field={@block[:collapsed]}
          class="block-action toggler"
          popover={gettext("Collapse (hide) block in block editor")}
        >
          <.icon :if={@collapsed} name="hero-eye-slash" />
          <.icon :if={!@collapsed} name="hero-eye" />
          <Input.input type={:checkbox} field={@block[:collapsed]} />
        </Form.label>

        <div
          :if={!@is_ref?}
          class="dirty block-action toggler"
          data-popover={gettext("Block has changes")}
          phx-click={JS.push("show_dirty", target: @target)}
        >
          ●
        </div>
      </div>
    </div>
    """
  end

  attr :block_data, :any, required: true
  attr :uid, :string, required: true
  attr :target, :any, required: true
  attr :table_template_name, :string

  def table(assigns) do
    table_rows_value = assigns.block_data[:table_rows].value

    valid? =
      table_rows_value not in [[], "", nil] &&
        !is_struct(table_rows_value, Ecto.Association.NotLoaded)

    assigns = assign(assigns, :valid?, valid?)

    ~H"""
    <div class="table-block-wrapper">
      <div class="table-info" phx-click="show_table_instructions" phx-target={@target}>
        <div class="icon">
          <span class="hero-table-cells"></span>
        </div>
        <div class="info">
          <span class="table-label">
            {gettext("Tabular data")}<br /> [{@table_template_name}]
          </span>
        </div>
      </div>
      <div class="table-block">
        <%= if !@valid? do %>
          <div class="block-instructions">
            <p>
              {gettext("This block implements tabular data, but the table is empty.")}<br />
              {gettext("Click the 'add row' button below to get started.")}
            </p>
            <button type="button" class="tiny" phx-click="add_table_row" phx-target={@target}>
              {gettext("Add row")}
            </button>
            <input type="hidden" name={@block_data[:table_rows].name} value={[]} />
          </div>
        <% else %>
          <div
            id={"sortable-#{@uid}-table-rows"}
            class="table-rows"
            phx-hook="Brando.SortableAssocs"
            data-target={@target}
            data-sortable-id={"sortable-#{@uid}-table-rows"}
            data-sortable-handle=".sort-handle"
            data-sortable-binary-keys="true"
            data-sortable-selector=".table-row"
            data-sortable-dispatch-event="true"
          >
            <.inputs_for :let={table_row} field={@block_data[:table_rows]} skip_hidden>
              <div class="table-row draggable" data-id={table_row.index}>
                <input type="hidden" name={table_row[:id].name} value={table_row[:id].value} />
                <input type="hidden" name={table_row[:_persistent_id].name} value={table_row.index} />
                <input type="hidden" name={"#{@block_data.name}[sort_table_row_ids][]"} value={table_row.index} />
                <div class="subform-tools">
                  <button type="button" class="sort-handle">
                    <.icon name="hero-arrows-up-down" />
                  </button>
                  <button
                    type="button"
                    class="delete-image"
                    name={"#{@block_data.name}[drop_table_row_ids][]"}
                    value={table_row.index}
                    phx-click={JS.dispatch("change")}
                  >
                    <.icon name="hero-x-mark" />
                  </button>
                </div>

                <.inputs_for :let={var} field={table_row[:vars]}>
                  <.live_component
                    module={RenderVar}
                    id={"block-#{@uid}-table-row-#{var.id}"}
                    var={var}
                    render={:all}
                    publish
                  />
                </.inputs_for>
              </div>
              <div class="insert-row">
                <button type="button" class="tiny" phx-click="add_table_row" phx-target={@target}>
                  {gettext("Add row")}
                </button>
              </div>
            </.inputs_for>
            <input type="hidden" name={"#{@block_data.name}[drop_table_row_ids][]"} />
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  attr :block_data, :any, required: true
  attr :module_datasource_module_label, :string, required: true
  attr :module_datasource_type, :string, required: true
  attr :module_datasource_query, :string, required: true
  attr :datasource_meta, :any, default: nil
  attr :uid, :string, required: true
  attr :target, :any, required: true
  attr :available_identifiers, :any, default: []
  attr :block_identifiers, :any, default: []

  def datasource(assigns) do
    translated_module_datasource_type =
      Gettext.dgettext(
        Brando.Gettext,
        "datasource",
        to_string(assigns.module_datasource_type)
      )

    assigns =
      assign(
        assigns,
        :translated_module_datasource_type,
        translated_module_datasource_type
      )

    ~H"""
    <div class="block-datasource">
      <div class="datasource-info" phx-click="show_datasource_instructions" phx-target={@target}>
        <div class="icon">
          <.icon name="hero-circle-stack" />
        </div>
        <div class="info">
          <span class="datasource-label">
            {gettext("Datasource")} [{@translated_module_datasource_type}]<br />
            {@module_datasource_module_label} &rarr; {@module_datasource_query}
          </span>
        </div>
      </div>

      <%= if @module_datasource_type == :selection do %>
        <Content.modal title={gettext("Select entries")} id={"select-entries-#{@uid}"} remember_scroll_position narrow>
          <h2 class="titlecase">{gettext("Available entries")}</h2>
          <Entries.block_identifier
            :for={identifier <- @available_identifiers}
            identifier={identifier}
            select={JS.push("select_identifier", value: %{id: identifier.id}, target: @target)}
            available_identifiers={@available_identifiers}
            block_identifiers={@block_identifiers}
          />
        </Content.modal>

        <div class="module-datasource-selected">
          <div
            id={"sortable-#{@uid}-identifiers"}
            class="selected-entries"
            phx-hook="Brando.SortableAssocs"
            data-target={@target}
            data-sortable-id={"sortable-#{@uid}-identifiers"}
            data-sortable-handle=".identifier"
            data-sortable-selector=".identifier"
            data-sortable-dispatch-event="true"
          >
            <.inputs_for :let={block_identifier} field={@block_identifiers}>
              <Entries.block_identifier block_identifier={block_identifier} available_identifiers={@available_identifiers}>
                <input
                  type="hidden"
                  name={"#{@block_identifiers.form.name}[sort_block_identifier_ids][]"}
                  value={block_identifier.index}
                />
                <:delete>
                  <button
                    type="button"
                    name={"#{@block_identifiers.form.name}[drop_block_identifier_ids][]"}
                    value={block_identifier.index}
                    phx-click={JS.dispatch("change")}
                  >
                    <.icon name="hero-x-circle" />
                  </button>
                </:delete>
                <:meta :let={identifier}>
                  <.identifier_meta
                    :if={@datasource_meta != []}
                    datasource_meta={@datasource_meta}
                    identifier={identifier}
                    block_data={@block_data}
                  />
                </:meta>
              </Entries.block_identifier>
            </.inputs_for>
            <input type="hidden" name={"#{@block_identifiers.form.name}[drop_block_identifier_ids][]"} />
          </div>

          <button
            class="tiny select-button"
            type="button"
            phx-click={
              "assign_available_identifiers"
              |> JS.push(target: @target)
              |> show_modal("#select-entries-#{@uid}")
            }
          >
            {gettext("Select entries")}
          </button>
        </div>
      <% end %>
    </div>
    """
  end

  attr :datasource_meta, :any, required: true
  attr :identifier, :any, required: true
  attr :block_data, :any, required: true

  def identifier_meta(%{datasource_meta: nil} = assigns) do
    ~H""
  end

  def identifier_meta(assigns) do
    datasource_meta = assigns.datasource_meta
    block_data = assigns.block_data
    identifier = assigns.identifier

    key = "#{inspect(identifier.schema)}_#{identifier.entry_id}"

    # Get current identifier_metas or initialize empty map
    current_metas = block_data[:identifier_metas].value || %{}

    # Initialize empty meta structure for this identifier if missing
    identifier_metas =
      if Map.has_key?(current_metas, key) do
        current_metas
        # Create default meta map with empty values for all fields
      else
        default_meta =
          Map.new(datasource_meta, fn field -> {to_string(field.key), nil} end)

        Map.put(current_metas, key, default_meta)
      end

    this_meta = Map.get(identifier_metas, key)

    meta_form =
      to_form(
        this_meta,
        as: "#{block_data.name}[identifier_metas][#{key}]"
      )

    assigns =
      assigns
      |> assign(:key, key)
      |> assign(:meta_form, meta_form)

    ~H"""
    <div :if={@datasource_meta != []} class="identifier-meta">
      <div class="meta-fields">
        <div :for={field <- @datasource_meta} class="meta-field">
          <%= case field.type do %>
            <% :text -> %>
              <Input.text field={@meta_form[field.key]} opts={field.opts} label={field.label} />
            <% :rich_text -> %>
              <Input.rich_text field={@meta_form[field.key]} opts={field.opts} label={field.label} />
            <% :textarea -> %>
              <Input.textarea field={@meta_form[field.key]} opts={field.opts} label={field.label} />
            <% :toggle -> %>
              <Input.checkbox field={@meta_form[field.key]} opts={field.opts} label={field.label} />
            <% :date -> %>
              <Input.date field={@meta_form[field.key]} opts={field.opts} label={field.label} />
            <% :datetime -> %>
              <Input.date field={@meta_form[field.key]} opts={field.opts} label={field.label} />
          <% end %>
        </div>
      </div>
    </div>
    """
  end

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

  def send_form_to_parent_stream(socket) do
    parent_cid = socket.assigns.parent_cid
    level = socket.assigns.level
    form = socket.assigns.form

    send_update(parent_cid, %{event: "update_block", level: level, form: form})
    socket
  end

  def maybe_update_live_preview_block(%{assigns: %{live_preview_active?: true}} = socket) do
    %{
      form: %{source: changeset},
      belongs_to: belongs_to,
      has_children?: has_children?,
      form_cid: form_cid
    } = socket.assigns

    block_cs = get_block_changeset(changeset, belongs_to)
    rendered_html = Changeset.get_field(block_cs, :rendered_html)
    uid = Changeset.get_field(block_cs, :uid)

    send_update(form_cid, %{
      event: "update_live_preview_block",
      rendered_html: rendered_html,
      uid: uid,
      has_children?: has_children?
    })

    socket
  end

  def maybe_update_live_preview_block(socket), do: socket

  def get_fragment(nil), do: nil

  def get_fragment(id) do
    Brando.Pages.get_fragment!(%{
      matches: %{id: id}
    })
  end

  def get_container(id) do
    {:ok, containers} =
      Brando.Content.list_containers(%{
        preload: [:palette],
        cache: {:ttl, :infinite}
      })

    case Enum.find(containers, &(&1.id == id)) do
      nil -> nil
      container -> container
    end
  end

  def get_module(id) do
    {:ok, modules} =
      Brando.Content.list_modules(%{
        preload: [{:vars, {Var, [asc: :sequence]}}],
        cache: {:ttl, :infinite}
      })

    case Enum.find(modules, &(&1.id == id)) do
      nil -> nil
      module -> module
    end
  end

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

  def render_and_update_block_changeset(changeset, entry, has_vars?, has_table_rows?) do
    rendered_html = render_block_html(changeset, entry, has_vars?, has_table_rows?, false, true)

    changeset
    |> Changeset.put_change(:rendered_html, rendered_html)
    |> maybe_update_rendered_at()
  end

  defp render_block_html(changeset, entry, has_vars?, has_table_rows?, is_root, skip_children) do
    changeset
    |> Brando.Utils.apply_changes_recursively()
    |> reset_empty_vars(has_vars?, is_root)
    |> reset_table_rows(has_table_rows?, is_root)
    |> Brando.Villain.render_block(entry,
      skip_children: skip_children,
      format_html: true,
      annotate_blocks: true
    )
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

    if path = Brando.Utils.try_path(entry, var_path ++ [:path]) do
      Brando.Utils.media_url(path)
    else
      ""
    end
  end

  defp liquid_render_module_picture_src(var_name, vars) do
    # TODO: Give this another shake now that we have assocs
    # FIXME
    #
    # This is suboptimal at best. We preload all our image vars in the form, but when running
    # the polymorphic changesets, it clobbers the image's `value` - resetting it.
    #
    # Everything here will hopefully improve when we can update poly changesets instead
    # of replacing/inserting new every time.
    if var_cs = Enum.find(vars, &(Changeset.get_field(&1, :key) == var_name)) do
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
    else
      ""
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

  def insert_identifier(block_identifiers, identifier_id) do
    new_block_identifier =
      %BlockIdentifier{}
      |> Changeset.change()
      |> Changeset.put_change(:identifier_id, identifier_id)
      |> Map.put(:action, :insert)

    block_identifiers ++ [new_block_identifier]
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

  defp extract_block_bg_color(%{colors: []}) do
    "transparent"
  end

  defp extract_block_bg_color(%{colors: colors}) do
    colors
    |> List.first()
    |> Map.get(:hex_value)
    |> Kernel.<>("14")
  end

  defp extract_block_bg_color(_) do
    "transparent"
  end
end
