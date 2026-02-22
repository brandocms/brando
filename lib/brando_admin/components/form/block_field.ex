defmodule BrandoAdmin.Components.Form.BlockField do
  @moduledoc false
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.Villain
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.BlockField.ModulePicker
  alias Ecto.Changeset

  def mount(socket) do
    {:ok, socket}
  end

  # duplicate block (that is an entry block)
  # this is received when the block is done gathering all its children changesets
  def update(%{event: "duplicate_block", uid: uid, changeset: changeset, populated: true}, socket) do
    block_module = socket.assigns.block_module
    block_cs = Changeset.get_assoc(changeset, :block)
    block_list = socket.assigns.block_list
    root_changesets = socket.assigns.root_changesets
    sequence = Enum.find_index(block_list, &(&1 == uid))
    new_sequence = sequence + 1
    current_user_id = socket.assigns.current_user.id
    entry_id = socket.assigns.entry.id
    new_uid = Brando.Utils.generate_uid()

    updated_block_cs =
      Villain.duplicate_block(block_cs, user_id: current_user_id, sequence: new_sequence, uid: new_uid)

    entry_block_cs =
      block_module
      |> struct(%{})
      |> Changeset.change(%{entry_id: entry_id})
      |> Changeset.put_assoc(:block, updated_block_cs)
      |> Map.put(:action, :insert)

    # insert the new block uid into the block_list
    new_block_list = List.insert_at(block_list, new_sequence, new_uid)

    entry_block_form =
      to_change_form(
        block_module,
        entry_block_cs,
        %{sequence: new_sequence},
        current_user_id
      )

    updated_root_changesets = insert_root_changeset(root_changesets, new_uid, new_sequence)

    socket
    |> update(:entry_blocks_forms, &List.insert_at(&1, new_sequence, entry_block_form))
    |> assign(:block_list, new_block_list)
    |> assign(:root_changesets, updated_root_changesets)
    |> update(:block_count, &(&1 + 1))
    |> reset_position_response_tracker()
    |> send_block_entry_position_update(new_block_list)
    |> then(&{:ok, &1})
  end

  def update(%{event: "duplicate_block", uid: uid, changeset: changeset, children: children}, socket) do
    block_module = socket.assigns.block_module
    block_list = socket.assigns.block_list
    root_changesets = socket.assigns.root_changesets
    sequence = Enum.find_index(block_list, &(&1 == uid))
    new_sequence = sequence + 1
    current_user_id = socket.assigns.current_user.id
    entry_id = socket.assigns.entry.id

    new_uid = Brando.Utils.generate_uid()
    block_cs = Changeset.get_assoc(changeset, :block)

    if children do
      # the block we wish to duplicate has children so we need to message
      # them to gather their changesets. We will do the duplication once we
      # have received all changesets.
      for {id, block_uid} <- children do
        send_update(Block,
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
      # the block has no children, duplicate it right away.
      updated_block_cs =
        Villain.duplicate_block(block_cs, user_id: current_user_id, sequence: new_sequence, uid: new_uid)

      entry_block_cs =
        block_module
        |> struct(%{})
        |> Changeset.change(%{entry_id: entry_id})
        |> Changeset.put_assoc(:block, updated_block_cs)
        |> Map.put(:action, :insert)

      # insert the new block uid into the block_list
      new_block_list = List.insert_at(block_list, new_sequence, new_uid)

      entry_block_form =
        to_change_form(
          block_module,
          entry_block_cs,
          %{sequence: new_sequence},
          current_user_id
        )

      updated_root_changesets = insert_root_changeset(root_changesets, new_uid, new_sequence)

      socket
      |> update(:entry_blocks_forms, &List.insert_at(&1, new_sequence, entry_block_form))
      |> assign(:block_list, new_block_list)
      |> assign(:root_changesets, updated_root_changesets)
      |> update(:block_count, &(&1 + 1))
      |> reset_position_response_tracker()
      |> send_block_entry_position_update(new_block_list)
      |> then(&{:ok, &1})
    end
  end

  # copy_block — no children (leaf block), store in clipboard immediately
  def update(%{event: "copy_block", changeset: changeset, children: nil, uid: _uid}, socket) do
    store_clipboard(socket, changeset)
  end

  # copy_block — populated (gathering complete), store in clipboard
  def update(%{event: "copy_block", changeset: changeset, uid: _uid, populated: true}, socket) do
    store_clipboard(socket, changeset)
  end

  # copy_block — has children, start gathering with action: :copy
  def update(%{event: "copy_block", changeset: _changeset, children: children, uid: uid}, socket)
      when not is_nil(children) do
    for {id, block_uid} <- children do
      send_update(Block,
        id: id,
        event: "fetch_changeset_for_duplication",
        uid: block_uid,
        parent_uid: uid,
        root_uid: uid,
        parent_sequence: 0,
        action: :copy
      )
    end

    {:ok, socket}
  end

  # paste_block — from a child block's inline paste button, forwarded up via Block
  def update(%{event: "paste_block", sequence: sequence}, socket) do
    {:ok, paste_root_block(socket, sequence)}
  end

  # paste_child_block — from a multi/container end paste button, forwarded up via Block
  def update(%{event: "paste_child_block", parent_cid: parent_cid, sequence: sequence}, socket) do
    user_id = socket.assigns.current_user.id
    clipboard = Brando.Cache.get({:block_clipboard, user_id})

    if clipboard do
      block_cs = create_duplicate_from_clipboard(clipboard, user_id)
      send_update(parent_cid, %{event: "insert_pasted_block", block_cs: block_cs, sequence: sequence})
    end

    {:ok, socket}
  end

  def update(%{event: "delete_block", uid: uid}, socket) do
    root_changesets = socket.assigns.root_changesets
    block_list = socket.assigns.block_list
    updated_root_changesets = delete_root_changeset(root_changesets, uid)
    new_block_list = List.delete(block_list, uid)

    socket
    |> assign(:root_changesets, updated_root_changesets)
    |> assign(:block_list, new_block_list)
    |> update(:entry_blocks_forms, fn forms ->
      Enum.reject(forms, &(get_form_block_uid(&1) == uid))
    end)
    |> update(:block_count, &(&1 - 1))
    |> reset_position_response_tracker()
    |> send_block_entry_position_update(new_block_list)
    |> then(&{:ok, &1})
  end

  def update(%{event: "update_root_sequence", sequence: sequence, form: form}, socket) do
    block_module = socket.assigns.block_module

    entry_block_form =
      to_change_form(
        block_module,
        form.source,
        %{sequence: sequence},
        socket.assigns.current_user.id
      )

    uid = get_form_block_uid(entry_block_form)
    updated = replace_form_by_uid(socket.assigns.entry_blocks_forms, uid, entry_block_form)
    {:ok, assign(socket, :entry_blocks_forms, updated)}
  end

  def update(%{event: "update_block", level: _level, form: form}, socket) do
    uid = get_form_block_uid(form)
    updated = replace_form_by_uid(socket.assigns.entry_blocks_forms, uid, form)
    {:ok, assign(socket, :entry_blocks_forms, updated)}
  end

  def update(%{event: "provide_root_block", changeset: changeset, uid: uid, tag: tag}, socket) do
    root_changesets = socket.assigns.root_changesets
    form_cid = socket.assigns.form_cid
    block_field = socket.assigns.block_field
    updated_root_changesets = update_root_changeset(root_changesets, uid, changeset)

    if Enum.any?(updated_root_changesets, &(elem(&1, 1) == nil)) do
      {:ok, assign(socket, :root_changesets, updated_root_changesets)}
    else
      send_update(form_cid, %{
        event: "provide_root_blocks",
        root_changesets: updated_root_changesets,
        block_field: block_field,
        tag: tag
      })

      {:ok, assign(socket, :root_changesets, updated_root_changesets)}
    end
  end

  # INSERT ROOT BLOCK
  def update(%{event: "insert_block", sequence: sequence, module_id: module_id}, socket) do
    module_id = String.to_integer(module_id)
    root_changesets = socket.assigns.root_changesets
    block_module = socket.assigns.block_module
    user_id = socket.assigns.current_user.id
    parent_id = nil
    source = socket.assigns.block_module
    empty_block_cs = build_block(module_id, user_id, parent_id, source, :module)

    sequence = (is_integer(sequence) && sequence) || String.to_integer(sequence)

    entry_block_cs =
      block_module
      |> struct(%{})
      |> Changeset.change(%{entry_id: socket.assigns.entry.id})
      |> Changeset.put_assoc(:block, empty_block_cs)
      |> Changeset.put_change(:sequence, sequence)
      |> Map.put(:action, :insert)

    uid = Changeset.get_field(empty_block_cs, :uid)

    # insert the new block uid into the block_list
    block_list = socket.assigns.block_list
    new_block_list = List.insert_at(block_list, sequence, uid)

    entry_block_form =
      to_form(entry_block_cs,
        as: "entry_block",
        id: "entry_block_form-#{uid}"
      )

    updated_root_changesets = insert_root_changeset(root_changesets, uid, sequence)

    selector = "[data-block-uid=\"#{uid}\"]"

    socket
    |> update(:entry_blocks_forms, &List.insert_at(&1, sequence, entry_block_form))
    |> assign(:block_list, new_block_list)
    |> assign(:root_changesets, updated_root_changesets)
    |> update(:block_count, &(&1 + 1))
    |> reset_position_response_tracker()
    |> send_block_entry_position_update(new_block_list)
    |> push_event("b:scroll_to", %{selector: selector})
    |> then(&{:ok, &1})
  end

  def update(%{event: "insert_container", sequence: sequence}, socket) do
    root_changesets = socket.assigns.root_changesets
    block_module = socket.assigns.block_module
    user_id = socket.assigns.current_user.id
    parent_id = nil
    source = socket.assigns.block_module
    empty_block_cs = build_container(user_id, parent_id, source)
    sequence = (is_integer(sequence) && sequence) || String.to_integer(sequence)

    entry_block_cs =
      block_module
      |> struct(%{})
      |> Changeset.change(%{entry_id: socket.assigns.entry.id})
      |> Changeset.put_assoc(:block, empty_block_cs)

    uid = Changeset.get_field(empty_block_cs, :uid)

    # insert the new block uid into the block_list
    block_list = socket.assigns.block_list
    new_block_list = List.insert_at(block_list, sequence, uid)

    entry_block_form =
      to_change_form(
        block_module,
        entry_block_cs,
        %{sequence: sequence},
        socket.assigns.current_user.id
      )

    updated_root_changesets = insert_root_changeset(root_changesets, uid, sequence)

    socket
    |> update(:entry_blocks_forms, &List.insert_at(&1, sequence, entry_block_form))
    |> assign(:block_list, new_block_list)
    |> update(:block_count, &(&1 + 1))
    |> assign(:root_changesets, updated_root_changesets)
    |> reset_position_response_tracker()
    |> send_block_entry_position_update(new_block_list)
    |> then(&{:ok, &1})
  end

  def update(%{event: "insert_fragment", sequence: sequence}, socket) do
    root_changesets = socket.assigns.root_changesets
    block_module = socket.assigns.block_module
    user_id = socket.assigns.current_user.id
    parent_id = nil
    source = socket.assigns.block_module
    empty_block_cs = build_fragment(user_id, parent_id, source)

    sequence = (is_integer(sequence) && sequence) || String.to_integer(sequence)

    entry_block_cs =
      block_module
      |> struct(%{})
      |> Changeset.change(%{entry_id: socket.assigns.entry.id})
      |> Changeset.put_assoc(:block, empty_block_cs)
      |> Map.put(:action, :insert)

    uid = Changeset.get_field(empty_block_cs, :uid)

    # insert the new block uid into the block_list
    block_list = socket.assigns.block_list
    new_block_list = List.insert_at(block_list, sequence, uid)

    entry_block_form =
      to_form(entry_block_cs,
        as: "entry_block",
        id: "entry_block_form-#{uid}"
      )

    updated_root_changesets = insert_root_changeset(root_changesets, uid, sequence)

    socket
    |> update(:entry_blocks_forms, &List.insert_at(&1, sequence, entry_block_form))
    |> assign(:block_list, new_block_list)
    |> assign(:root_changesets, updated_root_changesets)
    |> update(:block_count, &(&1 + 1))
    |> reset_position_response_tracker()
    |> send_block_entry_position_update(new_block_list)
    |> then(&{:ok, &1})
  end

  def update(%{event: "fetch_root_blocks", tag: tag}, socket) do
    block_list = socket.assigns.block_list
    block_field = socket.assigns.block_field
    form_cid = socket.assigns.form_cid

    if block_list == [] do
      if tag == :save do
        send(self(), {:progress_popup, "Providing root blocks..."})
      end

      send_update(form_cid, %{
        event: "provide_root_blocks",
        root_changesets: [],
        block_field: block_field,
        tag: tag
      })
    else
      # for each root block in block_list, send_update requesting their changeset
      for block_uid <- block_list do
        send_update(
          Block,
          id: "block-#{block_uid}",
          event: "fetch_root_block",
          tag: tag
        )
      end
    end

    {:ok, socket}
  end

  def update(%{event: "fetch_root_renders"}, socket) do
    block_list = socket.assigns.block_list
    block_field = socket.assigns.block_field
    form_cid = socket.assigns.form_cid

    if block_list == [] do
      send_update(form_cid, %{
        event: "provide_root_renders",
        renders: [],
        block_field: block_field
      })
    else
      # for each root block in block_list, send_update requesting their rendered_html
      for block_uid <- block_list do
        send_update(Block, id: "block-#{block_uid}", event: "fetch_root_render")
      end
    end

    then(socket, &{:ok, &1})
  end

  def update(%{event: "clear_root_changesets"}, socket) do
    block_list = socket.assigns.block_list
    # for each root block in block_list, send_update to clear their (child) changesets
    for block_uid <- block_list do
      send_update(Block, id: "block-#{block_uid}", event: "clear_changesets")
    end

    cleared_root_changesets = Enum.map(socket.assigns.root_changesets, &{elem(&1, 0), nil})
    {:ok, assign(socket, :root_changesets, cleared_root_changesets)}
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

  def update(%{event: "enable_live_preview", cache_key: cache_key}, socket) do
    block_list = socket.assigns.block_list

    for block_uid <- block_list do
      send_update(Block,
        id: "block-#{block_uid}",
        event: "enable_live_preview",
        cache_key: cache_key
      )
    end

    {:ok, socket}
  end

  def update(%{event: "disable_live_preview"}, socket) do
    block_list = socket.assigns.block_list

    for block_uid <- block_list do
      send_update(Block,
        id: "block-#{block_uid}",
        event: "disable_live_preview"
      )
    end

    {:ok, socket}
  end

  def update(%{event: "reload_all_blocks"}, socket) do
    {:ok, reload_all_blocks(socket)}
  end

  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> initialize_blocks(assigns)
    |> assign_templates()
    |> assign_module_set()
    |> reset_position_response_tracker()
    |> then(&{:ok, &1})
  end

  defp initialize_blocks(%{assigns: %{blocks_initialized: true}} = socket, _assigns), do: socket

  defp initialize_blocks(socket, assigns) do
    block_module = assigns.block_module
    user_id = assigns.current_user.id
    entry_blocks = assigns.entry_blocks || []
    entry_blocks_forms = Enum.map(entry_blocks, &to_change_form(block_module, &1, %{}, user_id))
    block_list = Enum.map(entry_blocks, & &1.block.uid)

    socket
    |> assign(:entry_blocks_forms, entry_blocks_forms)
    |> assign(:block_list, block_list)
    |> assign(:block_count, length(block_list))
    |> assign(:root_changesets, Enum.map(entry_blocks, &{&1.block.uid, nil}))
    |> assign(:module_picker_id, "#block-field-#{assigns.block_field}-module-picker")
    |> assign(:clipboard_meta, nil)
    |> send_block_entry_position_update(block_list)
    |> assign(:blocks_initialized, true)
  end

  defp reload_all_blocks(socket) do
    user_id = socket.assigns.current_user.id
    block_module = socket.assigns.block_module
    entry_blocks = socket.assigns.entry_blocks || []
    entry_blocks_forms = Enum.map(entry_blocks, &to_change_form(block_module, &1, %{}, user_id))
    block_list = Enum.map(entry_blocks, & &1.block.uid)

    socket
    |> assign(:entry_blocks_forms, entry_blocks_forms)
    |> assign(:block_list, block_list)
    |> assign(:block_count, length(block_list))
    |> assign(:root_changesets, Enum.map(entry_blocks, &{&1.block.uid, nil}))
  end

  defp get_form_block_uid(form) do
    block_cs = Changeset.get_assoc(form.source, :block)
    Changeset.get_field(block_cs, :uid)
  end

  defp replace_form_by_uid(forms, target_uid, new_form) do
    Enum.map(forms, fn form ->
      if get_form_block_uid(form) == target_uid, do: new_form, else: form
    end)
  end

  defdelegate update_root_changeset(root_changesets, uid, new_changeset),
    to: BrandoAdmin.Components.Form.BlockChangesetList,
    as: :update_changeset

  defdelegate insert_root_changeset(root_changesets, uid, position),
    to: BrandoAdmin.Components.Form.BlockChangesetList,
    as: :insert_changeset

  defdelegate delete_root_changeset(root_changesets, uid),
    to: BrandoAdmin.Components.Form.BlockChangesetList,
    as: :delete_changeset

  # reposition a main block
  def handle_event("reposition", %{"new" => new_idx, "old" => old_idx}, socket) when new_idx == old_idx do
    # same index, no move needed
    {:noreply, socket}
  end

  def handle_event("reposition", %{"uid" => id, "new" => new_idx, "old" => old_idx}, socket) do
    block_list = socket.assigns.block_list
    root_changesets = socket.assigns.root_changesets

    new_block_list =
      block_list
      |> List.delete_at(old_idx)
      |> List.insert_at(new_idx, id)

    # we must reposition the root_changesets list according to the new block_list
    new_root_changesets =
      Enum.map(new_block_list, fn uid ->
        Enum.find(root_changesets, fn
          {^uid, _} -> true
          _ -> false
        end)
      end)

    # reorder entry_blocks_forms to match new block_list order
    new_forms =
      Enum.map(new_block_list, fn uid ->
        Enum.find(socket.assigns.entry_blocks_forms, &(get_form_block_uid(&1) == uid))
      end)

    socket
    |> assign(:entry_blocks_forms, new_forms)
    |> assign(:block_list, new_block_list)
    |> assign(:root_changesets, new_root_changesets)
    |> reset_position_response_tracker()
    |> send_block_entry_position_update(new_block_list)
    |> then(&{:noreply, &1})
  end

  def handle_event("paste_block_at_end", _, socket) do
    {:noreply, paste_root_block(socket, socket.assigns.block_count)}
  end

  def handle_event("show_block_picker", _, socket) do
    # message block picker
    block_picker_id = "block-field-#{socket.assigns.block_field}-module-picker"
    block_count = socket.assigns.block_count
    module_set = socket.assigns.module_set

    send_update(ModulePicker,
      id: block_picker_id,
      event: :show_module_picker,
      filter: %{parent_id: nil, namespace: module_set},
      module_set: module_set,
      type: :module,
      sequence: block_count + 1,
      parent_cid: socket.assigns.myself
    )

    {:noreply, socket}
  end

  @doc """
  Recover blocks after a WebSocket reconnect where the LV process died.

  The JS BlockField hook captures all block form data to sessionStorage on
  disconnect. On reconnect, it compares stored UIDs against what's currently
  rendered and sends any missing blocks here for reconstruction.

  The recovered form params are run through the normal changeset pipeline
  (`block_module.changeset`), so all form field values — vars, refs,
  table_rows — are properly cast and restored, not just the block structure.
  """
  def handle_event("recover_blocks", params, socket) do
    %{"rootUids" => root_uids, "missingUids" => missing_uids, "forms" => forms} = params

    if missing_uids == [] do
      {:noreply, socket}
    else
      block_module = socket.assigns.block_module
      user_id = socket.assigns.current_user.id
      entry_id = socket.assigns.entry.id
      missing_set = MapSet.new(missing_uids)

      # Build forms for missing blocks by casting recovered params through
      # the normal changeset pipeline — this preserves all form field values
      recovered_forms =
        for uid <- missing_uids, reduce: %{} do
          acc ->
            form_id = "entry_block_form-#{uid}"
            form_data = forms[form_id]

            if form_data do
              entry_block_params = form_data["entry_block"] || %{}

              # Create base struct with an empty block so cast_assoc has
              # a loaded association to work with (not NotLoaded)
              base_block = %Brando.Content.Block{
                vars: [],
                refs: [],
                table_rows: [],
                children: [],
                block_identifiers: []
              }

              base_struct = block_module |> struct(%{}) |> Map.put(:block, base_block)

              # Include entry_id in params (no hidden field for it in the form)
              params_with_entry = Map.put(entry_block_params, "entry_id", to_string(entry_id))

              entry_block_cs =
                block_module.changeset(base_struct, params_with_entry, user_id)
                |> Map.put(:action, :insert)

              block_cs = Changeset.get_assoc(entry_block_cs, :block)
              recovered_uid = Changeset.get_field(block_cs, :uid)

              entry_block_form =
                to_form(entry_block_cs,
                  as: "entry_block",
                  id: "entry_block_form-#{recovered_uid}"
                )

              Map.put(acc, recovered_uid, entry_block_form)
            else
              acc
            end
        end

      if recovered_forms == %{} do
        {:noreply, socket}
      else
        # Rebuild the full ordered list: existing forms + recovered forms
        # in the original root_uids order
        current_forms_by_uid =
          Map.new(socket.assigns.entry_blocks_forms, &{get_form_block_uid(&1), &1})

        {merged_forms, merged_uids} =
          root_uids
          |> Enum.with_index()
          |> Enum.reduce({[], []}, fn {uid, sequence}, {forms_acc, uids_acc} ->
            form =
              if MapSet.member?(missing_set, uid) do
                recovered_forms[uid]
              else
                current_forms_by_uid[uid]
              end

            if form do
              form =
                to_change_form(block_module, form.source, %{sequence: sequence}, user_id)

              {forms_acc ++ [form], uids_acc ++ [uid]}
            else
              {forms_acc, uids_acc}
            end
          end)

        socket
        |> assign(:entry_blocks_forms, merged_forms)
        |> assign(:block_list, merged_uids)
        |> assign(:block_count, length(merged_uids))
        |> assign(:root_changesets, Enum.map(merged_uids, &{&1, nil}))
        |> reset_position_response_tracker()
        |> send_block_entry_position_update(merged_uids)
        |> then(&{:noreply, &1})
      end
    end
  end

  defdelegate reset_position_response_tracker(socket),
    to: BrandoAdmin.Components.Form.BlockChangesetList

  def send_block_entry_position_update(socket, block_list) do
    for {block_uid, idx} <- Enum.with_index(block_list) do
      send_update(Block, id: "block-#{block_uid}", event: "update_sequence", sequence: idx)
    end

    socket
  end

  def render(assigns) do
    ~H"""
    <div
      id={"#{@id}-wrapper"}
      phx-hook="Brando.BlockField"
      class="blocks-wrapper"
      data-block-field={"#{@form_name}[#{@block_field}]"}
    >
      <div class="label-wrapper ">
        <label class="control-label" data-field-presence={"#{@form_name}[#{@block_field}]"}>
          <span>{gettext("Blocks")}</span>
          <div class="field-presence" phx-update="ignore" id={"#{@form_name}[#{@block_field}]-field-presence"}></div>
        </label>
      </div>
      <div class="blocks-content">
        <.live_component
          module={BrandoAdmin.Components.Form.BlockField.ModulePicker}
          id={"block-field-#{@block_field}-module-picker"}
          templates={[]}
          hide_fragments={false}
          hide_sections={false}
        />
        <%= if @block_count == 0 do %>
          <div class="blocks-empty-instructions">
            {gettext("Click the plus to start adding content blocks")}
            <%= if @templates && @templates != [] do %>
              <br />{gettext("or get started with a prefab'ed template")}:<br />
              <div class="blocks-templates">
                <%= for template <- @templates do %>
                  <button type="button" phx-click={JS.push("use_template", target: @myself)} phx-value-id={template.id}>
                    {template.name}<br />
                    <small>{template.instructions}</small>
                  </button>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>

        <div
          id={"block-field-#{@block_field}"}
          phx-hook="Brando.SortableBlocks"
          data-sortable-id="sortable-blocks"
          data-sortable-handle=".sort-handle"
          data-sortable-selector=".block"
        >
          <%= for entry_block_form <- @entry_blocks_forms do %>
            <.inputs_for :let={block} field={entry_block_form[:block]} skip_hidden>
              <div
                id={"base-#{block[:uid].value}"}
                data-id={entry_block_form[:id].value}
                data-uid={block[:uid].value}
                class="entry-block draggable"
              >
                <.live_component
                  module={Block}
                  id={"block-#{block[:uid].value}"}
                  block_module={@block_module}
                  block_field={@block_field}
                  children={block[:children].value}
                  parent_uploads={@parent_uploads}
                  parent_cid={@myself}
                  parent_uid={}
                  parent_path={[]}
                  module_set={@module_set}
                  entry={@entry}
                  form={entry_block_form}
                  form_cid={@form_cid}
                  current_user_id={@current_user.id}
                  belongs_to={:root}
                  clipboard_meta={@clipboard_meta}
                  level={0}
                />
              </div>
            </.inputs_for>
          <% end %>
        </div>

        <Block.plus
          click={JS.push("show_block_picker", target: @myself) |> show_modal(@module_picker_id)}
          clipboard_meta={@clipboard_meta}
          paste_context={:root}
          paste_click={JS.push("paste_block_at_end", target: @myself)}
        />
      </div>
    </div>
    """
  end

  def to_change_form(block_module, entry_block_or_cs, params, user_id, action \\ nil) do
    changeset =
      entry_block_or_cs
      |> block_module.changeset(params, user_id)
      |> Map.put(:action, action)

    block_cs = Changeset.get_assoc(changeset, :block)
    uid = Changeset.get_field(block_cs, :uid)

    to_form(changeset,
      as: "entry_block",
      id: "entry_block_form-#{uid}"
    )
  end

  def build_block(module_id, user_id, parent_id, source, type) do
    module = get_module(module_id)
    # Generate fresh refs with new UIDs when creating blocks from modules
    fresh_refs =
      (module.refs || [])
      |> Brando.Villain.remove_pk_from_refs()
      |> Enum.map(&Map.put(&1, :uid, Brando.Utils.generate_uid()))

    cleaned_vars = Brando.Villain.remove_pk_from_vars(module.vars)

    # Create clean ref structs
    cleaned_refs =
      Enum.map(fresh_refs, fn ref ->
        %Brando.Content.Ref{
          name: ref.name,
          description: ref.description,
          data: ref.data,
          sequence: ref.sequence,
          uid: ref.uid
        }
      end)

    block_changeset =
      %Brando.Content.Block{}
      |> Changeset.change(%{
        uid: Brando.Utils.generate_uid(),
        type: type,
        creator_id: user_id,
        module_id: module_id,
        parent_id: parent_id,
        multi: module.multi,
        source: source,
        children: [],
        block_identifiers: [],
        table_rows: []
      })
      |> Changeset.put_assoc(:vars, cleaned_vars)
      |> Changeset.put_assoc(:refs, cleaned_refs)
      |> Map.put(:action, :insert)

    block_changeset
  end

  def build_fragment(user_id, parent_id, source) do
    Changeset.change(
      %Brando.Content.Block{},
      %{
        uid: Brando.Utils.generate_uid(),
        type: :fragment,
        creator_id: user_id,
        parent_id: parent_id,
        fragment_id: nil,
        multi: false,
        source: source,
        children: [],
        block_identifiers: [],
        table_rows: [],
        vars: [],
        refs: []
      }
    )
  end

  def build_container(user_id, parent_id, source) do
    Changeset.change(%Brando.Content.Block{}, %{
      uid: Brando.Utils.generate_uid(),
      type: :container,
      creator_id: user_id,
      parent_id: parent_id,
      source: source,
      children: [],
      table_rows: [],
      vars: [],
      refs: []
    })
  end

  defp get_module(module_id), do: Brando.Content.fetch_module(module_id)

  defp assign_templates(socket) do
    assign_new(socket, :templates, fn ->
      if template_namespace = socket.assigns.opts[:template_namespace] do
        Brando.Content.list_templates!(%{filter: %{namespace: template_namespace}})
      end
    end)
  end

  defp assign_module_set(socket) do
    assign_new(socket, :module_set, fn ->
      opts = socket.assigns.opts
      opts[:module_set] || "all"
    end)
  end

  ## Clipboard helpers

  defp store_clipboard(socket, changeset) do
    user_id = socket.assigns.current_user.id

    # Extract block type and module_id from the changeset
    {type, module_id} =
      if Map.has_key?(changeset.data, :block) do
        # Entry block wrapper — get inner block
        bc = Changeset.get_assoc(changeset, :block)
        {Changeset.get_field(bc, :type), Changeset.get_field(bc, :module_id)}
      else
        # Direct block (child)
        {Changeset.get_field(changeset, :type), Changeset.get_field(changeset, :module_id)}
      end

    # For module_entry blocks, look up the child module definition's parent_id
    # which is the parent module definition's id (for smart matching in can_paste?)
    parent_mid =
      if type == :module_entry && module_id do
        module = get_module(module_id)
        module && module.parent_id
      end

    clipboard = %{changeset: changeset, type: type, parent_module_id: parent_mid}
    Brando.Cache.put({:block_clipboard, user_id}, clipboard)

    clipboard_meta = %{type: type, parent_module_id: parent_mid}

    socket
    |> assign(:clipboard_meta, clipboard_meta)
    |> then(&{:ok, &1})
  end

  defp paste_root_block(socket, sequence) do
    user_id = socket.assigns.current_user.id
    clipboard = Brando.Cache.get({:block_clipboard, user_id})

    if clipboard do
      insert_pasted_root_block(socket, clipboard, sequence)
    else
      socket
    end
  end

  defp insert_pasted_root_block(socket, clipboard, sequence) do
    block_module = socket.assigns.block_module
    current_user_id = socket.assigns.current_user.id
    entry_id = socket.assigns.entry.id

    # The clipboard changeset may be an entry_block or a direct block.
    # Extract the inner block changeset.
    block_cs = extract_block_changeset(clipboard.changeset)
    new_uid = Brando.Utils.generate_uid()

    updated_block_cs =
      Villain.duplicate_block(block_cs, user_id: current_user_id, sequence: sequence, uid: new_uid)

    entry_block_cs =
      block_module
      |> struct(%{})
      |> Changeset.change(%{entry_id: entry_id})
      |> Changeset.put_assoc(:block, updated_block_cs)
      |> Map.put(:action, :insert)

    # insert the new block uid into the block_list
    block_list = socket.assigns.block_list
    root_changesets = socket.assigns.root_changesets
    new_block_list = List.insert_at(block_list, sequence, new_uid)

    entry_block_form =
      to_change_form(
        block_module,
        entry_block_cs,
        %{sequence: sequence},
        current_user_id
      )

    updated_root_changesets = insert_root_changeset(root_changesets, new_uid, sequence)
    selector = "[data-block-uid=\"#{new_uid}\"]"

    socket
    |> update(:entry_blocks_forms, &List.insert_at(&1, sequence, entry_block_form))
    |> assign(:block_list, new_block_list)
    |> assign(:root_changesets, updated_root_changesets)
    |> update(:block_count, &(&1 + 1))
    |> reset_position_response_tracker()
    |> send_block_entry_position_update(new_block_list)
    |> push_event("b:scroll_to", %{selector: selector})
  end

  defp create_duplicate_from_clipboard(clipboard, user_id) do
    block_cs = extract_block_changeset(clipboard.changeset)
    Villain.duplicate_block(block_cs, user_id: user_id)
  end

  defp extract_block_changeset(src_changeset) do
    if Map.has_key?(src_changeset.data, :block) do
      Changeset.get_assoc(src_changeset, :block)
    else
      src_changeset
    end
  end
end
