defmodule BrandoAdmin.Components.Form.BlockField do
  @moduledoc """
  The owner of a block field's tree state: root order, nesting structure and
  the uid-keyed param-diff store (`BlockField.Ops`).

  ## State ownership (Phase 3 single-owner architecture)

  * **This component owns**: the op store (`@block_ops` — order, parents,
    child order, diffs, statuses, db ids, deleted list), the root block list,
    clipboard meta, and the outline drawer.
  * **Each `Block` live_component owns its editing state exclusively** —
    forms never travel between components after mount. This component's
    `@entry_blocks_forms` are *mount-time seeds only*; they are never pushed
    back down to reconcile with mounted blocks.
  * **Mutations arrive as named ops** (`update/2` clause for `"block_op"`),
    emitted by blocks at every commit point via `Block.emit_block_op/2`, or
    applied directly here for root-level structure (insert/delete/reorder/
    paste/duplicate). `apply_block_op/2` runs the pure reducer; a rejected op
    logs an error — that's a drift signal, investigate it.

  ## Save / preview / share

  `fetch_root_blocks` materializes every root changeset from the op store in
  one pass (`Ops.materialize_root/2`) and answers the Form — there is no
  gather protocol. After a completed save, `reload_all_blocks/1` re-seeds
  every mounted block through the `replace_form` cascade (fresh db ids), the
  only sanctioned parent→child form handoff after mount.

  ## Multi-user sync

  Blur ships `Ops.subtree_snapshot/2` over PubSub; receiving fields merge via
  `Ops.apply_remote_snapshot/3`, re-materialize the affected root and hand
  the fresh form to the mounted component (`apply_remote_block_ops` clause).
  Structural broadcasts (add/delete/reorder) are mirrored into both the
  legacy list assigns and the op store.

  ## Restorable bin (delete undo)

  Every local delete stashes an `Ops.bin_snapshot/2` in `@block_bin` before
  the delete op runs; an undo toast offers LIFO restore. Restoring replays
  the snapshot into the store (`Ops.restore_snapshot/2`), then re-mounts a
  root from its re-materialized seed form or hands a child's root the
  `replace_form` cascade. Restores broadcast so other editors' stores
  resurrect the block too. The bin clears on save — the save deletes the
  underlying rows, so stashed db ids go stale.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  alias Brando.Content.Blocks, as: ContentBlocks
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.BlockField.ModulePicker
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias BrandoAdmin.Components.Form.BlockField.Outline
  alias Ecto.Changeset

  require Logger

  def mount(socket) do
    {:ok, assign(socket, :outline_items, [])}
  end

  # duplicate block (that is an entry block)
  # this is received when the block is done gathering all its children changesets
  def update(%{event: "duplicate_block", uid: uid, changeset: changeset, populated: true}, socket) do
    block_module = socket.assigns.block_module
    block_cs = Changeset.get_assoc(changeset, :block)
    block_list = socket.assigns.block_list
    sequence = Enum.find_index(block_list, &(&1 == uid))
    new_sequence = sequence + 1
    current_user_id = socket.assigns.current_user.id
    entry_id = socket.assigns.entry.id
    new_uid = Brando.Utils.generate_uid()

    updated_block_cs =
      ContentBlocks.duplicate_block(block_cs, user_id: current_user_id, sequence: new_sequence, uid: new_uid)

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

    socket
    |> update(:entry_blocks_forms, &List.insert_at(&1, new_sequence, entry_block_form))
    |> assign(:block_list, new_block_list)
    |> update(:block_count, &(&1 + 1))
    |> apply_block_op({:insert, new_uid, new_sequence, Ops.block_diff_params(entry_block_cs)})
    |> refresh_live_preview()
    |> then(&{:ok, &1})
  end

  def update(%{event: "duplicate_block", uid: uid, changeset: changeset, children: children}, socket) do
    block_module = socket.assigns.block_module
    block_list = socket.assigns.block_list
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
        ContentBlocks.duplicate_block(block_cs, user_id: current_user_id, sequence: new_sequence, uid: new_uid)

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

      socket
      |> update(:entry_blocks_forms, &List.insert_at(&1, new_sequence, entry_block_form))
      |> assign(:block_list, new_block_list)
      |> update(:block_count, &(&1 + 1))
      |> apply_block_op({:insert, new_uid, new_sequence, Ops.block_diff_params(entry_block_cs)})
      |> refresh_live_preview()
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
  def update(%{event: "paste_child_block", parent_ref: parent_ref, sequence: sequence}, socket) do
    user_id = socket.assigns.current_user.id
    clipboard = Brando.Cache.get({:block_clipboard, user_id})

    if clipboard do
      block_cs = create_duplicate_from_clipboard(clipboard, user_id)
      send_to_ref(parent_ref, %{event: "insert_pasted_block", block_cs: block_cs, sequence: sequence})
    end

    {:ok, socket}
  end

  def update(%{event: "delete_block", uid: uid}, socket) do
    # Broadcast to other users
    if topic = socket.assigns[:blocks_topic] do
      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        topic,
        {:block_deleted, %{uid: uid, user_id: socket.assigns.current_user.id}}
      )
    end

    {:ok, socket |> stash_in_bin(uid) |> remove_block_from_state(uid)}
  end

  # blocks (any level) emit their content/structural ops directly — see
  # Block.emit_block_op/2. Forms never travel up; the seed forms in
  # entry_blocks_forms are only read at child mount.
  # Child deletes pass through the bin first — the op tears the subtree out
  # of the store, so the undo snapshot must be captured here.
  def update(%{event: "block_op", op: {:delete, uid} = op}, socket) do
    {:ok, socket |> stash_in_bin(uid) |> apply_block_op(op)}
  end

  def update(%{event: "block_op", op: op}, socket) do
    {:ok, apply_block_op(socket, op)}
  end

  # Outline: relay extracted child to target parent
  def update(
        %{event: "insert_extracted_child", target_parent_uid: target_uid, child_changeset: cs, sequence: seq},
        socket
      ) do
    send_update(Block,
      id: "block-#{target_uid}",
      event: "insert_pasted_block",
      block_cs: cs,
      sequence: seq
    )

    {:ok, rebuild_outline_items(socket)}
  end

  # INSERT ROOT BLOCK
  def update(%{event: "insert_block", sequence: sequence, module_id: module_id}, socket) do
    module_id = String.to_integer(module_id)
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

    selector = "[data-block-uid=\"#{uid}\"]"

    # Broadcast to other users
    if topic = socket.assigns[:blocks_topic] do
      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        topic,
        {:block_added, %{uid: uid, module_id: module_id, sequence: sequence, user_id: socket.assigns.current_user.id}}
      )
    end

    socket
    |> update(:entry_blocks_forms, &List.insert_at(&1, sequence, entry_block_form))
    |> assign(:block_list, new_block_list)
    |> update(:block_count, &(&1 + 1))
    |> apply_block_op({:insert, uid, sequence, Ops.block_diff_params(entry_block_cs)})
    |> refresh_live_preview()
    |> push_event("b:scroll_to", %{selector: selector})
    |> then(&{:ok, &1})
  end

  def update(%{event: "insert_container", sequence: sequence}, socket) do
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

    socket
    |> update(:entry_blocks_forms, &List.insert_at(&1, sequence, entry_block_form))
    |> assign(:block_list, new_block_list)
    |> update(:block_count, &(&1 + 1))
    |> apply_block_op({:insert, uid, sequence, Ops.block_diff_params(entry_block_cs)})
    |> refresh_live_preview()
    |> then(&{:ok, &1})
  end

  def update(%{event: "insert_fragment", sequence: sequence}, socket) do
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

    socket
    |> update(:entry_blocks_forms, &List.insert_at(&1, sequence, entry_block_form))
    |> assign(:block_list, new_block_list)
    |> update(:block_count, &(&1 + 1))
    |> apply_block_op({:insert, uid, sequence, Ops.block_diff_params(entry_block_cs)})
    |> refresh_live_preview()
    |> then(&{:ok, &1})
  end

  # Save, live preview and share all read the op store — the store is
  # commit-complete (every commit point emits a diff op), so ONE
  # materialization pass builds all root changesets for any tag. The old
  # recursive fetch/provide gather across the component tree is gone.
  def update(%{event: "fetch_root_blocks", tag: tag}, socket) do
    ops = socket.assigns.block_ops
    block_module = socket.assigns.block_module
    user_id = socket.assigns.current_user.id

    root_changesets =
      Enum.map(ops.order, fn uid ->
        # a materialization failure here must fail loudly — dropping a block
        # silently is worse than any crash. recursive?: true is load-bearing —
        # the default block cast drops "children" params entirely.
        {:ok, params} = Ops.materialize_root(ops, uid)
        {uid, block_module.changeset(materialize_base_struct(socket, uid), params, user_id, true)}
      end)

    send_update(BrandoAdmin.Components.Form,
      id: socket.assigns.form_id,
      event: "provide_root_blocks",
      root_changesets: root_changesets,
      block_field: socket.assigns.block_field,
      tag: tag
    )

    {:ok, socket}
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

  # === Block Sync: Data Shipping ===

  # Ship a blurred block's content to other editors as a subtree diff
  # snapshot straight from the op store — no component round-trip, no
  # changesets over PubSub, and child blocks ship too (the old
  # changeset-shipping path only ever covered root blocks).
  def update(%{event: "fetch_block_for_shipping", uid: uid}, socket) do
    topic = socket.assigns[:blocks_topic]
    ops = socket.assigns.block_ops

    if topic && Ops.known?(ops, uid) do
      Phoenix.PubSub.broadcast(Brando.pubsub(), topic, {
        :block_ops_shipped,
        %{uid: uid, snapshot: Ops.subtree_snapshot(ops, uid), user_id: socket.assigns.current_user.id}
      })
    end

    {:ok, socket}
  end

  # Apply a remote editor's subtree snapshot: merge it into the op store,
  # re-materialize the affected root and hand the fresh form to the mounted
  # component via the replace_form cascade (blocks own their forms — a seed
  # swap alone would never reach them). The remount_block push re-boots
  # Jupiter JS widgets inside the block.
  def update(%{event: "apply_remote_block_ops", uid: uid, snapshot: snapshot}, socket) do
    ops = socket.assigns.block_ops

    with {:ok, updated_ops} <- Ops.apply_remote_snapshot(ops, uid, snapshot),
         root_uid = Ops.root_of(updated_ops, uid),
         {:ok, params} <- Ops.materialize_root(updated_ops, root_uid) do
      block_module = socket.assigns.block_module
      user_id = socket.assigns.current_user.id

      new_form =
        socket
        |> materialize_base_struct(root_uid)
        |> block_module.changeset(params, user_id, true)
        |> to_form(as: "entry_block", id: "entry_block_form-#{root_uid}")

      send_update(Block, id: "block-#{root_uid}", event: "replace_form", form: new_form)

      {:ok,
       socket
       |> assign(:block_ops, updated_ops)
       |> assign(:entry_blocks_forms, replace_form_by_uid(socket.assigns.entry_blocks_forms, root_uid, new_form))
       |> push_event("b:component:remount_block", %{uid: root_uid})}
    else
      {:error, reason} ->
        Logger.warning(
          "BlockField (#{socket.assigns.block_field}) could not apply remote block ops " <>
            "for #{uid}: #{inspect(reason)}"
        )

        {:ok, socket}
    end
  end

  # === Block Sync: Structural Operations ===

  # Remote user added a block
  def update(
        %{
          event: "remote_block_added",
          uid: remote_uid,
          module_id: module_id,
          sequence: sequence,
          user_id: remote_user_id
        },
        socket
      ) do
    block_list = socket.assigns.block_list

    # Skip if we already have this block (dedup)
    if remote_uid in block_list do
      {:ok, socket}
    else
      block_module = socket.assigns.block_module
      source = socket.assigns.block_module

      empty_block_cs = build_block(module_id, remote_user_id, nil, source, :module)
      # Override UID to match the original
      empty_block_cs = Changeset.put_change(empty_block_cs, :uid, remote_uid)

      entry_block_cs =
        block_module
        |> struct(%{})
        |> Changeset.change(%{entry_id: socket.assigns.entry.id})
        |> Changeset.put_assoc(:block, empty_block_cs)
        |> Changeset.put_change(:sequence, sequence)
        |> Map.put(:action, :insert)

      # Clamp sequence to valid range
      clamped_sequence = min(sequence, length(block_list))

      new_block_list = List.insert_at(block_list, clamped_sequence, remote_uid)

      entry_block_form =
        to_form(entry_block_cs,
          as: "entry_block",
          id: "entry_block_form-#{remote_uid}"
        )

      socket
      |> update(:entry_blocks_forms, &List.insert_at(&1, clamped_sequence, entry_block_form))
      |> assign(:block_list, new_block_list)
      |> update(:block_count, &(&1 + 1))
      |> apply_block_op({:insert, remote_uid, clamped_sequence, Ops.block_diff_params(entry_block_cs)})
      |> refresh_live_preview()
      |> then(&{:ok, &1})
    end
  end

  # Remote user deleted a block. No bin stash — the undo toast belongs to
  # the deleting editor; their restore broadcasts back to us.
  def update(%{event: "remote_block_deleted", uid: uid}, socket) do
    if uid in socket.assigns.block_list do
      {:ok, remove_block_from_state(socket, uid)}
    else
      {:ok, socket}
    end
  end

  # Remote user undid a delete — replay their bin snapshot against our store.
  # The origin field guard matters: the Form fans sync events out to every
  # block field, and a root restore against the wrong field's store would
  # succeed (all uids unknown there) and duplicate the block.
  def update(%{event: "remote_block_restored", snapshot: snapshot, origin_block_field: origin}, socket) do
    if origin == socket.assigns.block_field do
      case restore_from_snapshot(socket, snapshot) do
        {:ok, socket} ->
          {:ok, socket}

        {:error, reason} ->
          Logger.warning(
            "BlockField (#{socket.assigns.block_field}) could not apply remote block restore: #{inspect(reason)}"
          )

          {:ok, socket}
      end
    else
      {:ok, socket}
    end
  end

  # Remote user reordered blocks
  def update(%{event: "remote_blocks_reordered", block_list: remote_block_list}, socket) do
    new_forms =
      Enum.map(remote_block_list, fn uid ->
        Enum.find(socket.assigns.entry_blocks_forms, &(get_form_block_uid(&1) == uid))
      end)
      |> Enum.reject(&is_nil/1)

    socket
    |> assign(:entry_blocks_forms, new_forms)
    |> assign(:block_list, remote_block_list)
    |> apply_block_op({:reorder, remote_block_list})
    |> refresh_live_preview()
    |> then(&{:ok, &1})
  end

  def update(assigns, socket) do
    socket
    |> assign(assigns)
    |> initialize_blocks(assigns)
    |> maybe_arm_blocks_topic()
    |> assign_module_set()
    |> then(&{:ok, &1})
  end

  # Create forms initialize with a nil-id entry, so no sync topic exists.
  # Arm it as soon as a persisted entry lands (post-create-save re-render) —
  # otherwise multi-user block sync stays disarmed until a full reload.
  defp maybe_arm_blocks_topic(%{assigns: %{blocks_topic: nil, entry: %{id: entry_id}}} = socket)
       when not is_nil(entry_id) do
    topic = "brando:blocks:#{entry_id}:#{socket.assigns.block_field}"
    Phoenix.PubSub.subscribe(Brando.pubsub(), topic)
    assign(socket, :blocks_topic, topic)
  end

  defp maybe_arm_blocks_topic(socket), do: socket

  defp initialize_blocks(%{assigns: %{blocks_initialized: true}} = socket, _assigns), do: socket

  defp initialize_blocks(socket, assigns) do
    block_module = assigns.block_module
    user_id = assigns.current_user.id
    entry_blocks = assigns.entry_blocks || []

    entry_blocks_forms = Enum.map(entry_blocks, &to_change_form(block_module, &1, %{}, user_id))
    block_list = Enum.map(entry_blocks, & &1.block.uid)

    # Subscribe to blocks sync topic for structural changes + data shipping
    entry_id = assigns.entry && assigns.entry.id
    blocks_topic = entry_id && "brando:blocks:#{entry_id}:#{assigns.block_field}"

    if blocks_topic do
      Phoenix.PubSub.subscribe(Brando.pubsub(), blocks_topic)
    end

    socket
    |> assign(:entry_blocks_forms, entry_blocks_forms)
    |> assign(:block_list, block_list)
    |> assign(:block_count, length(block_list))
    |> assign(:block_ops, Ops.from_entry_blocks(entry_blocks))
    |> assign(:module_picker_id, "#block-field-#{assigns.block_field}-module-picker")
    |> assign(:clipboard_meta, nil)
    |> assign(:block_bin, [])
    |> assign(:blocks_topic, blocks_topic)
    |> assign(:blocks_initialized, true)
  end

  # The changeset base for materializing a root block: its persisted entry
  # block when it exists, otherwise a fresh struct with an empty (loaded)
  # block so cast_assoc has something to cast against.
  defp materialize_base_struct(socket, uid) do
    case Enum.find(socket.assigns.entry_blocks || [], &(&1.block.uid == uid)) do
      nil ->
        base_block = %Brando.Content.Block{vars: [], refs: [], table_rows: [], children: [], block_identifiers: []}
        socket.assigns.block_module |> struct(%{}) |> Map.put(:block, base_block)

      entry_block ->
        entry_block
    end
  end

  # Strangler-phase op application (see `Ops` moduledoc): every mutation the
  # legacy cache performs is mirrored into the op state. A rejected op means
  # the op state and the cache have drifted — log it loudly, keep the socket
  # usable.
  defp apply_block_op(socket, op) do
    case Ops.apply_op(socket.assigns.block_ops, op) do
      {:ok, ops_state} ->
        assign(socket, :block_ops, ops_state)

      {:error, reason} ->
        Logger.error(
          "BlockField (#{socket.assigns.block_field}) rejected block op " <>
            "#{inspect(elem(op, 0))}: #{inspect(reason)}"
        )

        socket
    end
  end

  # Post-save re-seed. Blocks own their forms, so refreshed persisted data
  # (fresh db ids for rows inserted by the save) must be handed to each
  # mounted component explicitly — `replace_form` is the ONLY sanctioned
  # parent→child form handoff after mount, and it cascades down the tree.
  # Without it, a save-and-continue-editing session would keep diffing
  # against pre-save nil-id data and churn child rows on the next save.
  defp reload_all_blocks(socket) do
    user_id = socket.assigns.current_user.id
    block_module = socket.assigns.block_module
    entry_blocks = socket.assigns.entry_blocks || []

    entry_blocks_forms = Enum.map(entry_blocks, &to_change_form(block_module, &1, %{}, user_id))
    block_list = Enum.map(entry_blocks, & &1.block.uid)

    for form <- entry_blocks_forms do
      send_update(Block, id: "block-#{get_form_block_uid(form)}", event: "replace_form", form: form)
    end

    socket
    |> assign(:entry_blocks_forms, entry_blocks_forms)
    |> assign(:block_list, block_list)
    |> assign(:block_count, length(block_list))
    |> assign(:block_ops, Ops.from_entry_blocks(entry_blocks))
    # bin snapshots don't survive a save — the save deleted the underlying
    # rows, so their captured db ids are stale
    |> assign(:block_bin, [])
  end

  # Capture the doomed subtree for undo BEFORE the delete tears it down.
  # Local deletes only — the deleting editor gets the undo toast; restoring
  # broadcasts so every editor's store resurrects the block (leaving a uid in
  # a remote `deleted` list would kill the rows again on their next save).
  defp stash_in_bin(socket, uid) do
    ops = socket.assigns.block_ops

    if Ops.known?(ops, uid) do
      update(socket, :block_bin, &[Ops.bin_snapshot(ops, uid) | &1])
    else
      socket
    end
  end

  # Undo a delete: replay the bin snapshot into the op store, then bring the
  # block back on screen. A restored ROOT mounts a fresh component from its
  # re-materialized seed form (the keyed :for picks it up); a restored CHILD
  # lives inside a mounted parent that owns its form, so the root gets the
  # `replace_form` cascade + remount push — the same path remote-sync applies
  # use (the only sanctioned post-mount form handoff).
  defp restore_from_snapshot(socket, %{uids: [uid | _], location: location} = snapshot) do
    with {:ok, updated_ops} <- Ops.restore_snapshot(socket.assigns.block_ops, snapshot) do
      root_uid = Ops.root_of(updated_ops, uid)
      # a materialization failure here must fail loudly — see fetch_root_blocks
      {:ok, params} = Ops.materialize_root(updated_ops, root_uid)

      new_form =
        socket
        |> materialize_base_struct(root_uid)
        |> socket.assigns.block_module.changeset(params, socket.assigns.current_user.id, true)
        |> to_form(as: "entry_block", id: "entry_block_form-#{root_uid}")

      socket = assign(socket, :block_ops, updated_ops)

      socket =
        case location do
          {:root, _at} ->
            index = Enum.find_index(updated_ops.order, &(&1 == uid))

            socket
            |> update(:entry_blocks_forms, &List.insert_at(&1, index, new_form))
            |> assign(:block_list, updated_ops.order)
            |> update(:block_count, &(&1 + 1))

          {:child, _parent_uid, _at} ->
            send_update(Block, id: "block-#{root_uid}", event: "replace_form", form: new_form)

            socket
            |> assign(:entry_blocks_forms, replace_form_by_uid(socket.assigns.entry_blocks_forms, root_uid, new_form))
            |> push_event("b:component:remount_block", %{uid: root_uid})
        end

      {:ok, refresh_live_preview(socket)}
    end
  end

  defp remove_block_from_state(socket, uid) do
    block_list = socket.assigns.block_list
    new_block_list = List.delete(block_list, uid)

    socket
    |> assign(:block_list, new_block_list)
    |> update(:entry_blocks_forms, fn forms ->
      Enum.reject(forms, &(get_form_block_uid(&1) == uid))
    end)
    |> update(:block_count, &(&1 - 1))
    |> apply_block_op({:delete, uid})
    |> refresh_live_preview()
  end

  defp get_form_block_uid(form) do
    block_cs = Changeset.get_assoc(form.source, :block)
    Changeset.get_field(block_cs, :uid)
  end

  # Recovered blocks were never persisted (the fresh LV process re-initialized
  # from the DB, so anything missing from the render was unsaved) — they enter
  # the op state as inserts, then one reorder restores the pre-disconnect order.
  defp apply_recovered_block_ops(socket, merged_forms, merged_uids, missing_set) do
    forms_by_uid = Map.new(merged_forms, &{get_form_block_uid(&1), &1})

    merged_uids
    |> Enum.filter(&MapSet.member?(missing_set, &1))
    |> Enum.reduce(socket, fn uid, acc ->
      params = Ops.block_diff_params(forms_by_uid[uid].source)
      apply_block_op(acc, {:insert, uid, :end, params})
    end)
    |> apply_block_op({:reorder, merged_uids})
  end

  defp replace_form_by_uid(forms, target_uid, new_form) do
    Enum.map(forms, fn form ->
      if get_form_block_uid(form) == target_uid, do: new_form, else: form
    end)
  end

  # reposition a main block
  def handle_event("reposition", %{"new" => new_idx, "old" => old_idx}, socket) when new_idx == old_idx do
    # same index, no move needed
    {:noreply, socket}
  end

  def handle_event("reposition", %{"uid" => id, "new" => new_idx, "old" => old_idx}, socket) do
    block_list = socket.assigns.block_list

    new_block_list =
      block_list
      |> List.delete_at(old_idx)
      |> List.insert_at(new_idx, id)

    # reorder entry_blocks_forms to match new block_list order
    new_forms =
      Enum.map(new_block_list, fn uid ->
        Enum.find(socket.assigns.entry_blocks_forms, &(get_form_block_uid(&1) == uid))
      end)

    # Broadcast to other users
    if topic = socket.assigns[:blocks_topic] do
      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        topic,
        {:blocks_reordered, %{block_list: new_block_list, user_id: socket.assigns.current_user.id}}
      )
    end

    socket
    |> assign(:entry_blocks_forms, new_forms)
    |> assign(:block_list, new_block_list)
    |> apply_block_op({:reorder, new_block_list})
    |> refresh_live_preview()
    |> then(&{:noreply, &1})
  end

  def handle_event("paste_block_at_end", _, socket) do
    {:noreply, paste_root_block(socket, socket.assigns.block_count)}
  end

  # Undo the most recent delete (LIFO — a parent deleted after its child
  # restores first, so the child's snapshot finds its parent again).
  def handle_event("restore_block", _, socket) do
    case socket.assigns.block_bin do
      [] ->
        {:noreply, socket}

      [snapshot | rest] ->
        socket = assign(socket, :block_bin, rest)

        case restore_from_snapshot(socket, snapshot) do
          {:ok, socket} ->
            if topic = socket.assigns[:blocks_topic] do
              Phoenix.PubSub.broadcast(
                Brando.pubsub(),
                topic,
                {:block_restored,
                 %{
                   snapshot: snapshot,
                   block_field: socket.assigns.block_field,
                   user_id: socket.assigns.current_user.id
                 }}
              )
            end

            uid = hd(snapshot.uids)
            {:noreply, push_event(socket, "b:scroll_to", %{selector: "[data-block-uid=\"#{uid}\"]"})}

          {:error, reason} ->
            Logger.warning(
              "BlockField (#{socket.assigns.block_field}) could not restore deleted block: #{inspect(reason)}"
            )

            {:noreply, socket}
        end
    end
  end

  def handle_event("clear_block_bin", _, socket) do
    {:noreply, assign(socket, :block_bin, [])}
  end

  # Outline: rebuild items when drawer opens
  def handle_event("rebuild_outline", _, socket) do
    {:noreply, rebuild_outline_items(socket)}
  end

  # Collapse/expand: root blocks only
  def handle_event("collapse_root_blocks", _, socket) do
    {:noreply, set_root_blocks_collapsed(socket, true)}
  end

  def handle_event("expand_root_blocks", _, socket) do
    {:noreply, set_root_blocks_collapsed(socket, false)}
  end

  # Collapse/expand: multi block children only
  def handle_event("collapse_multi_children", _, socket) do
    {:noreply, set_multi_children_collapsed(socket, true)}
  end

  def handle_event("expand_multi_children", _, socket) do
    {:noreply, set_multi_children_collapsed(socket, false)}
  end

  # Outline: root block reorder
  def handle_event("outline_root_reposition", %{"new" => new_idx, "old" => old_idx}, socket)
      when new_idx == old_idx do
    {:noreply, socket}
  end

  def handle_event("outline_root_reposition", %{"uid" => id, "new" => new_idx, "old" => old_idx}, socket) do
    block_list = socket.assigns.block_list

    new_block_list =
      block_list
      |> List.delete_at(old_idx)
      |> List.insert_at(new_idx, id)

    new_forms =
      Enum.map(new_block_list, fn uid ->
        Enum.find(socket.assigns.entry_blocks_forms, &(get_form_block_uid(&1) == uid))
      end)

    # Broadcast to other users
    if topic = socket.assigns[:blocks_topic] do
      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        topic,
        {:blocks_reordered, %{block_list: new_block_list, user_id: socket.assigns.current_user.id}}
      )
    end

    socket
    |> assign(:entry_blocks_forms, new_forms)
    |> assign(:block_list, new_block_list)
    |> apply_block_op({:reorder, new_block_list})
    |> refresh_live_preview()
    |> rebuild_outline_items()
    |> then(&{:noreply, &1})
  end

  # Outline: click to scroll to block
  def handle_event("outline_scroll_to", %{"uid" => uid}, socket) do
    selector = "[data-block-uid=\"#{uid}\"]"
    {:noreply, push_event(socket, "b:scroll_to", %{selector: selector})}
  end

  # Outline: child reorder or cross-parent move
  def handle_event("outline_reposition", %{"new" => new_idx, "old" => old_idx}, socket)
      when new_idx == old_idx do
    {:noreply, socket}
  end

  def handle_event("outline_reposition", params, socket) do
    from_parent_uid = get_in(params, ["from", "parentUid"])
    to_parent_uid = get_in(params, ["to", "parentUid"])
    uid = params["uid"]
    old_idx = params["old"]
    new_idx = params["new"]

    if from_parent_uid == to_parent_uid do
      # Same parent: reorder children
      send_update(Block,
        id: "block-#{from_parent_uid}",
        event: "outline_reorder_child",
        child_uid: uid,
        old: old_idx,
        new: new_idx
      )
    else
      # Cross-parent: extract from source, insert into target
      send_update(Block,
        id: "block-#{from_parent_uid}",
        event: "extract_child",
        child_uid: uid,
        target_parent_uid: to_parent_uid,
        target_sequence: new_idx
      )
    end

    {:noreply, rebuild_outline_items(socket)}
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
      parent_ref: {__MODULE__, socket.assigns.id}
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
        |> apply_recovered_block_ops(merged_forms, merged_uids, missing_set)
        |> refresh_live_preview()
        |> then(&{:noreply, &1})
      end
    end
  end

  # Structural changes update the preview directly — sequence is derived
  # from list order at materialization, so there is no per-block restamp
  # round-trip (nor an ack barrier) to wait for anymore.
  defp refresh_live_preview(socket) do
    send_update(BrandoAdmin.Components.Form,
      id: socket.assigns.form_id,
      event: "update_live_preview"
    )

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
      <div class="label-wrapper">
        <label class="control-label" data-field-presence={"#{@form_name}[#{@block_field}]"}>
          <span>{gettext("Blocks")}</span>
          <div class="field-presence" phx-update="ignore" id={"#{@form_name}[#{@block_field}]-field-presence"}></div>
        </label>
      </div>
      <div class="blocks-content">
        <div :if={@block_count > 0} class="blocks-actions">
          <div class="block-field-dropdown">
            <button
              type="button"
              class="block-field-dropdown-toggle"
              phx-click={toggle_dropdown("#block-field-#{@block_field}-actions-dropdown")}
              phx-click-away={hide_dropdown("#block-field-#{@block_field}-actions-dropdown")}
            >
              <.icon name="hero-ellipsis-horizontal-circle" />
            </button>
            <ul
              class="block-field-dropdown-content hidden"
              id={"block-field-#{@block_field}-actions-dropdown"}
            >
              <li>
                <button
                  type="button"
                  phx-click={
                    JS.push("rebuild_outline", target: @myself)
                    |> toggle_drawer("#block-field-#{@block_field}-outline")
                    |> hide_dropdown("#block-field-#{@block_field}-actions-dropdown")
                  }
                >
                  <.icon name="hero-bars-3-bottom-left" /> {gettext("Block outline")}
                </button>
              </li>
              <li class="dropdown-separator"></li>
              <li>
                <button
                  type="button"
                  phx-click={
                    JS.push("collapse_root_blocks", target: @myself)
                    |> hide_dropdown("#block-field-#{@block_field}-actions-dropdown")
                  }
                >
                  <.icon name="hero-eye-slash" /> {gettext("Collapse root blocks")}
                </button>
              </li>
              <li>
                <button
                  type="button"
                  phx-click={
                    JS.push("expand_root_blocks", target: @myself)
                    |> hide_dropdown("#block-field-#{@block_field}-actions-dropdown")
                  }
                >
                  <.icon name="hero-eye" /> {gettext("Expand root blocks")}
                </button>
              </li>
              <li>
                <button
                  type="button"
                  phx-click={
                    JS.push("collapse_multi_children", target: @myself)
                    |> hide_dropdown("#block-field-#{@block_field}-actions-dropdown")
                  }
                >
                  <.icon name="hero-eye-slash" /> {gettext("Collapse multi blocks")}
                </button>
              </li>
              <li>
                <button
                  type="button"
                  phx-click={
                    JS.push("expand_multi_children", target: @myself)
                    |> hide_dropdown("#block-field-#{@block_field}-actions-dropdown")
                  }
                >
                  <.icon name="hero-eye" /> {gettext("Expand multi blocks")}
                </button>
              </li>
            </ul>
          </div>
        </div>
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
          </div>
        <% end %>

        <div
          id={"block-field-#{@block_field}"}
          phx-hook="Brando.SortableBlocks"
          data-sortable-id="sortable-blocks"
          data-sortable-handle=".sort-handle"
          data-sortable-selector=".block"
        >
          <.inputs_for
            :let={block}
            :for={{entry_block_form, list_index} <- Enum.with_index(@entry_blocks_forms)}
            :key={get_form_block_uid(entry_block_form)}
            field={entry_block_form[:block]}
            skip_hidden
          >
            <div
              id={"base-#{block[:uid].value}"}
              data-id={entry_block_form[:id].value}
              data-uid={block[:uid].value}
              class="entry-block draggable"
            >
              <.live_component
                module={Block}
                id={"block-#{block[:uid].value}"}
                list_index={list_index}
                block_module={@block_module}
                block_field={@block_field}
                children={block[:children].value}
                parent_ref={{__MODULE__, @id}}
                parent_uid={}
                parent_path={[]}
                module_set={@module_set}
                entry={@entry}
                form={entry_block_form}
                form_id={@form_id}
                current_user_id={@current_user.id}
                belongs_to={:root}
                clipboard_meta={@clipboard_meta}
                level={0}
              />
            </div>
          </.inputs_for>
        </div>

        <Block.plus
          click={JS.push("show_block_picker", target: @myself) |> show_modal(@module_picker_id)}
          clipboard_meta={@clipboard_meta}
          paste_context={:root}
          paste_click={JS.push("paste_block_at_end", target: @myself)}
        />
        <div :if={@block_bin != []} id={"block-field-#{@block_field}-bin"} class="block-bin-toast" data-testid="block-bin">
          <span class="block-bin-message">
            {ngettext("Block deleted", "%{count} blocks deleted", length(@block_bin))}
          </span>
          <button type="button" class="block-bin-undo" phx-click="restore_block" phx-target={@myself}>
            {gettext("Undo")}
          </button>
          <button
            type="button"
            class="block-bin-dismiss"
            phx-click="clear_block_bin"
            phx-target={@myself}
            aria-label={gettext("Dismiss")}
          >
            <.icon name="hero-x-mark" />
          </button>
        </div>
      </div>
      <Outline.outline_drawer
        id={"block-field-#{@block_field}-outline"}
        outline_items={@outline_items}
        block_field={@block_field}
        target={@myself}
      />
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
      |> Brando.Content.Blocks.remove_pk_from_refs()
      |> Enum.map(&Map.put(&1, :uid, Brando.Utils.generate_uid()))

    cleaned_vars = Brando.Content.Blocks.remove_pk_from_vars(module.vars)

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

  defp rebuild_outline_items(socket) do
    assign(socket, :outline_items, Outline.build_outline_items(socket.assigns.entry_blocks_forms))
  end

  defp set_root_blocks_collapsed(socket, collapsed) do
    for block_uid <- socket.assigns.block_list do
      send_update(Block, id: "block-#{block_uid}", event: "set_collapsed", collapsed: collapsed)
    end

    socket
  end

  defp set_multi_children_collapsed(socket, collapsed) do
    for form <- socket.assigns.entry_blocks_forms do
      block_cs = Changeset.get_assoc(form.source, :block)
      block_uid = Changeset.get_field(block_cs, :uid)
      module_id = Changeset.get_field(block_cs, :module_id)

      if module_id do
        case Brando.Content.fetch_module(module_id) do
          %{multi: true} ->
            send_update(Block,
              id: "block-#{block_uid}",
              event: "set_children_collapsed",
              collapsed: collapsed
            )

          _ ->
            :ok
        end
      end
    end

    socket
  end

  defp get_module(module_id), do: Brando.Content.fetch_module(module_id)

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
      ContentBlocks.duplicate_block(block_cs, user_id: current_user_id, sequence: sequence, uid: new_uid)

    entry_block_cs =
      block_module
      |> struct(%{})
      |> Changeset.change(%{entry_id: entry_id})
      |> Changeset.put_assoc(:block, updated_block_cs)
      |> Map.put(:action, :insert)

    # insert the new block uid into the block_list
    block_list = socket.assigns.block_list
    new_block_list = List.insert_at(block_list, sequence, new_uid)

    entry_block_form =
      to_change_form(
        block_module,
        entry_block_cs,
        %{sequence: sequence},
        current_user_id
      )

    selector = "[data-block-uid=\"#{new_uid}\"]"

    socket
    |> update(:entry_blocks_forms, &List.insert_at(&1, sequence, entry_block_form))
    |> assign(:block_list, new_block_list)
    |> update(:block_count, &(&1 + 1))
    |> apply_block_op({:insert, new_uid, sequence, Ops.block_diff_params(entry_block_cs)})
    |> refresh_live_preview()
    |> push_event("b:scroll_to", %{selector: selector})
  end

  defp create_duplicate_from_clipboard(clipboard, user_id) do
    block_cs = extract_block_changeset(clipboard.changeset)
    ContentBlocks.duplicate_block(block_cs, user_id: user_id)
  end

  defp extract_block_changeset(src_changeset) do
    if Map.has_key?(src_changeset.data, :block) do
      Changeset.get_assoc(src_changeset, :block)
    else
      src_changeset
    end
  end
end
