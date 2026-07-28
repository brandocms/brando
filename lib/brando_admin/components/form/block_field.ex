defmodule BrandoAdmin.Components.Form.BlockField do
  @moduledoc """
  The owner of a block field's tree state: root order, nesting structure and
  the uid-keyed param-diff store (`BlockField.Ops`).

  ## State ownership (Phase 3 single-owner architecture)

  * **This component owns**: the op store (`@block_ops` — order, parents,
    child order, diffs, statuses, db ids, deleted list), clipboard meta, the
    restorable bin and the outline drawer. `@root_order` is the store's
    render projection (assigned only through `assign_ops/2`, so it cannot
    drift); the keyed `:for` renders shells straight from it.
  * **Each `Block` live_component owns its editing state exclusively** —
    forms never travel between components after mount. `@seed_forms` is a
    uid-keyed map of *mount-time seeds only*: a Block reads its form from it
    once at first mount; entries are put on insert and dropped on delete,
    never reordered, never reconciled.
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

  Content ships as `Ops.subtree_snapshot/2` over PubSub when a block's
  editing session settles (focusout + settle delay in the Block JS hook,
  focus switch, pre-save force-ship); child structural ops ship their root
  immediately. Snapshots carry delete tombstones so remote child deletes
  replicate. Receivers merge via `Ops.apply_remote_snapshot/3` and hand the
  mounted root a fresh form through the replace_form cascade — unless the
  local user is editing inside that root, in which case the snapshot parks
  in `@pending_remote_snapshots` and applies on their blur (never dropped).
  `ship_or_flush/2` never re-broadcasts an unchanged snapshot
  (`@last_synced_snapshots`), so blurring an untouched block cannot clobber
  newer remote edits; concurrent same-block edits resolve last-editor-wins.
  Late joiners broadcast a sync request on mount; any editor whose store
  diverged from the database (`@blocks_changed?`) replays its state as the
  standard structural + snapshot messages.

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
    sequence = Enum.find_index(socket.assigns.block_ops.order, &(&1 == uid))
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

    entry_block_form =
      to_change_form(
        block_module,
        entry_block_cs,
        %{sequence: new_sequence},
        current_user_id
      )

    socket
    |> put_seed_form(new_uid, entry_block_form)
    |> apply_block_op({:insert, new_uid, new_sequence, Ops.block_diff_params(entry_block_cs)})
    |> refresh_live_preview()
    |> then(&{:ok, &1})
  end

  def update(%{event: "duplicate_block", uid: uid, changeset: changeset, children: children}, socket) do
    block_module = socket.assigns.block_module
    sequence = Enum.find_index(socket.assigns.block_ops.order, &(&1 == uid))
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

      entry_block_form =
        to_change_form(
          block_module,
          entry_block_cs,
          %{sequence: new_sequence},
          current_user_id
        )

      socket
      |> put_seed_form(new_uid, entry_block_form)
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
  # Block.emit_block_op/2. Forms never travel up; seed forms are only read
  # at first mount.
  # Child deletes pass through the bin first — the op tears the subtree out
  # of the store, so the undo snapshot must be captured here. Child
  # structural ops ship their root's subtree immediately: they never had a
  # broadcast of their own (only root-level add/delete/reorder do), so a
  # remote editor would only learn of them on the next content blur.
  def update(%{event: "block_op", op: {:delete, uid} = op}, socket) do
    root_uid = Ops.root_of(socket.assigns.block_ops, uid)

    {:ok,
     socket
     |> stash_in_bin(uid)
     |> apply_block_op(op)
     |> ship_or_flush(root_uid)}
  end

  def update(%{event: "block_op", op: {:insert_child, parent_uid, _uid, _at, _params} = op}, socket) do
    socket = apply_block_op(socket, op)
    {:ok, ship_or_flush(socket, parent_uid)}
  end

  def update(%{event: "block_op", op: {:reorder_children, parent_uid, _uids} = op}, socket) do
    socket = apply_block_op(socket, op)
    {:ok, ship_or_flush(socket, parent_uid)}
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
    |> put_seed_form(uid, entry_block_form)
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

    entry_block_form =
      to_change_form(
        block_module,
        entry_block_cs,
        %{sequence: sequence},
        socket.assigns.current_user.id
      )

    socket
    |> put_seed_form(uid, entry_block_form)
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

    entry_block_form =
      to_form(entry_block_cs,
        as: "entry_block",
        id: "entry_block_form-#{uid}"
      )

    socket
    |> put_seed_form(uid, entry_block_form)
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
    for block_uid <- socket.assigns.block_ops.order do
      send_update(Block,
        id: "block-#{block_uid}",
        event: "enable_live_preview",
        cache_key: cache_key
      )
    end

    {:ok, socket}
  end

  def update(%{event: "disable_live_preview"}, socket) do
    for block_uid <- socket.assigns.block_ops.order do
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

  # Blur/settle (or force-ship before save) for `uid`'s root.
  def update(%{event: "fetch_block_for_shipping", uid: uid}, socket) do
    {:ok, ship_or_flush(socket, uid)}
  end

  # A remote editor shipped a subtree snapshot. If we're currently editing
  # inside the same root, applying would replace the form under our own
  # typing — defer it instead (latest snapshot wins); `ship_or_flush/2`
  # applies it when we leave the block. Otherwise apply immediately.
  def update(%{event: "apply_remote_block_ops", uid: uid, snapshot: snapshot} = msg, socket) do
    ops = socket.assigns.block_ops
    focused_uid = Map.get(msg, :focused_uid)
    root_uid = if Ops.known?(ops, uid), do: Ops.root_of(ops, uid), else: uid

    focused_same_root? =
      focused_uid && Ops.known?(ops, focused_uid) && Ops.root_of(ops, focused_uid) == root_uid

    if focused_same_root? do
      {:ok, update(socket, :pending_remote_snapshots, &Map.put(&1, root_uid, %{uid: uid, snapshot: snapshot}))}
    else
      {:ok, apply_remote_root_snapshot(socket, uid, snapshot)}
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
    # Skip if we already have this block (dedup)
    if Ops.known?(socket.assigns.block_ops, remote_uid) do
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

      entry_block_form =
        to_form(entry_block_cs,
          as: "entry_block",
          id: "entry_block_form-#{remote_uid}"
        )

      socket
      |> put_seed_form(remote_uid, entry_block_form)
      |> apply_block_op({:insert, remote_uid, sequence, Ops.block_diff_params(entry_block_cs)})
      |> refresh_live_preview()
      |> then(&{:ok, &1})
    end
  end

  # Remote user deleted a block. No bin stash — the undo toast belongs to
  # the deleting editor; their restore broadcasts back to us.
  def update(%{event: "remote_block_deleted", uid: uid}, socket) do
    if uid in socket.assigns.block_ops.order do
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

  # A late joiner asked for unsaved state. If our store diverged from the
  # database, replay it as the standard sync messages IN ORDER (PubSub
  # preserves per-publisher ordering): structural adds for inserted module
  # roots → content snapshots for dirty roots → root deletes → final order.
  # The joiner's existing receive paths handle each. A clean store stays
  # silent — the database it just loaded is already the truth.
  def update(%{event: "remote_sync_requested", origin_block_field: origin}, socket) do
    ops = socket.assigns.block_ops
    topic = socket.assigns[:blocks_topic]

    if origin == socket.assigns.block_field and socket.assigns.blocks_changed? and topic do
      user_id = socket.assigns.current_user.id

      ops.order
      |> Enum.with_index()
      |> Enum.each(fn {uid, index} ->
        with :inserted <- ops.statuses[uid],
             module_id when not is_nil(module_id) <- get_in(ops.diffs, [uid, "block", "module_id"]) do
          Phoenix.PubSub.broadcast(
            Brando.pubsub(),
            topic,
            {:block_added, %{uid: uid, module_id: module_id, sequence: index, user_id: user_id}}
          )
        end
      end)

      socket =
        Enum.reduce(ops.order, socket, fn uid, acc ->
          snapshot = Ops.subtree_snapshot(ops, uid)

          if snapshot_dirty?(snapshot) do
            acc
            |> broadcast_snapshot(uid, snapshot)
            |> record_synced_snapshot(uid, snapshot)
          else
            acc
          end
        end)

      Enum.each(ops.deleted_roots, fn uid ->
        Phoenix.PubSub.broadcast(Brando.pubsub(), topic, {:block_deleted, %{uid: uid, user_id: user_id}})
      end)

      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        topic,
        {:blocks_reordered, %{block_list: ops.order, user_id: user_id}}
      )

      {:ok, socket}
    else
      {:ok, socket}
    end
  end

  # Remote user reordered blocks
  def update(%{event: "remote_blocks_reordered", block_list: remote_block_list}, socket) do
    socket
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

    socket
    |> assign(:blocks_topic, topic)
    |> request_blocks_sync()
  end

  defp maybe_arm_blocks_topic(socket), do: socket

  # Late-joiner catch-up: ask already-connected editors for their unsaved
  # state. We initialize from the database, but another editor's uncommitted
  # edits live only in their op store — without this, a joiner sees stale
  # content until the next blur-ship happens to arrive.
  defp request_blocks_sync(socket) do
    if topic = socket.assigns[:blocks_topic] do
      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        topic,
        {:blocks_sync_request, %{block_field: socket.assigns.block_field, user_id: socket.assigns.current_user.id}}
      )
    end

    socket
  end

  defp initialize_blocks(%{assigns: %{blocks_initialized: true}} = socket, _assigns), do: socket

  defp initialize_blocks(socket, assigns) do
    block_module = assigns.block_module
    user_id = assigns.current_user.id
    entry_blocks = assigns.entry_blocks || []

    entry_blocks_forms = Enum.map(entry_blocks, &to_change_form(block_module, &1, %{}, user_id))

    # Subscribe to blocks sync topic for structural changes + data shipping
    entry_id = assigns.entry && assigns.entry.id
    blocks_topic = entry_id && "brando:blocks:#{entry_id}:#{assigns.block_field}"

    if blocks_topic do
      Phoenix.PubSub.subscribe(Brando.pubsub(), blocks_topic)
    end

    socket
    |> assign(:seed_forms, Map.new(entry_blocks_forms, &{get_form_block_uid(&1), &1}))
    |> assign_ops(Ops.from_entry_blocks(entry_blocks))
    # Bare id, not a selector — consumed by `data-ui-modal-show`.
    |> assign(:module_picker_id, "block-field-#{assigns.block_field}-module-picker")
    |> assign(:clipboard_meta, nil)
    |> assign(:block_bin, [])
    |> assign(:pending_remote_snapshots, %{})
    |> assign(:last_synced_snapshots, %{})
    |> assign(:blocks_changed?, false)
    |> assign(:blocks_topic, blocks_topic)
    |> assign(:blocks_initialized, true)
    |> request_blocks_sync()
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

  # The op chokepoint: every mutation (structural or content, local or
  # remote) lands here. A rejected op means a caller drifted from the store —
  # log it loudly, keep the socket usable.
  defp apply_block_op(socket, op) do
    case Ops.apply_op(socket.assigns.block_ops, op) do
      {:ok, ops_state} ->
        socket
        |> assign_ops(ops_state)
        |> assign(:blocks_changed?, true)

      {:error, reason} ->
        Logger.error(
          "BlockField (#{socket.assigns.block_field}) rejected block op " <>
            "#{inspect(elem(op, 0))}: #{inspect(reason)}"
        )

        socket
    end
  end

  # `root_order` is the render projection of the store — assigned together
  # with `block_ops` so they can never drift. `assign/3` no-ops on equal
  # values, so content-only ops (order list untouched, reference-equal) never
  # dirty `root_order` and typing never re-evaluates the shell comprehension.
  defp assign_ops(socket, ops_state) do
    socket
    |> assign(:block_ops, ops_state)
    |> assign(:root_order, ops_state.order)
  end

  # Seed forms exist for one purpose: a Block component reads its form from
  # them ONCE at first mount (update/2 drops the assign afterwards). They are
  # only ever put (insert paths) or dropped (delete) — never reordered, never
  # reconciled. Structure lives in the op store alone.
  defp put_seed_form(socket, uid, form) do
    update(socket, :seed_forms, &Map.put(&1, uid, form))
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

    for form <- entry_blocks_forms do
      send_update(Block, id: "block-#{get_form_block_uid(form)}", event: "replace_form", form: form)
    end

    socket
    |> assign(:seed_forms, Map.new(entry_blocks_forms, &{get_form_block_uid(&1), &1}))
    |> assign_ops(Ops.from_entry_blocks(entry_blocks))
    # bin snapshots don't survive a save — the save deleted the underlying
    # rows, so their captured db ids are stale. Sync bookkeeping resets with
    # the store: the persisted data is the new shared baseline.
    |> assign(:block_bin, [])
    |> assign(:pending_remote_snapshots, %{})
    |> assign(:last_synced_snapshots, %{})
    |> assign(:blocks_changed?, false)
  end

  # Ship or catch up on `uid`'s root when its editing session settles (blur,
  # focus-switch, structural child op, pre-save force-ship). Three outcomes:
  #
  # * we edited since the last sync → broadcast our snapshot (concurrent
  #   same-block edits resolve last-editor-wins) and drop any deferred
  #   remote snapshot for it;
  # * we didn't edit but a remote snapshot was deferred while we were
  #   focused → apply it now;
  # * nothing changed on either side → no-op. Never re-broadcast an
  #   unchanged snapshot: shipping stale state would clobber newer remote
  #   edits on the other editors.
  defp ship_or_flush(socket, uid) do
    ops = socket.assigns.block_ops

    if Ops.known?(ops, uid) do
      root_uid = Ops.root_of(ops, uid)
      snapshot = Ops.subtree_snapshot(ops, root_uid)
      pending = socket.assigns.pending_remote_snapshots[root_uid]

      edited? =
        case socket.assigns.last_synced_snapshots[root_uid] do
          nil -> snapshot_dirty?(snapshot)
          last_synced -> snapshot != last_synced
        end

      cond do
        edited? ->
          socket
          |> broadcast_snapshot(root_uid, snapshot)
          |> record_synced_snapshot(root_uid, snapshot)
          |> update(:pending_remote_snapshots, &Map.delete(&1, root_uid))

        pending ->
          socket
          |> update(:pending_remote_snapshots, &Map.delete(&1, root_uid))
          |> apply_remote_root_snapshot(pending.uid, pending.snapshot)

        true ->
          socket
      end
    else
      socket
    end
  end

  # A subtree with no diffs and no tombstones matches persisted data — an
  # untouched block has nothing worth broadcasting.
  defp snapshot_dirty?(snapshot) do
    snapshot.deleted != [] or Enum.any?(snapshot.uids, &(Map.get(snapshot.diffs, &1, %{}) != %{}))
  end

  defp broadcast_snapshot(socket, root_uid, snapshot) do
    if topic = socket.assigns[:blocks_topic] do
      Phoenix.PubSub.broadcast(Brando.pubsub(), topic, {
        :block_ops_shipped,
        %{uid: root_uid, snapshot: snapshot, user_id: socket.assigns.current_user.id}
      })
    end

    socket
  end

  defp record_synced_snapshot(socket, root_uid, snapshot) do
    update(socket, :last_synced_snapshots, &Map.put(&1, root_uid, snapshot))
  end

  # Merge a remote snapshot into the op store, re-materialize the affected
  # root and hand the fresh form to the mounted component via the
  # replace_form cascade (blocks own their forms — a seed swap alone would
  # never reach them). The remount_block push re-boots JS widgets inside
  # the block. Records the post-apply snapshot so our own next blur
  # compares as unchanged instead of echoing it back.
  defp apply_remote_root_snapshot(socket, uid, snapshot) do
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

      # remount_js: the Block pushes the widget-remount event itself so it
      # rides the SAME diff frame as the form patch — pushed from here it
      # dispatches before the patch and widgets re-boot with stale content
      send_update(Block, id: "block-#{root_uid}", event: "replace_form", form: new_form, remount_js: true)

      socket
      |> assign_ops(updated_ops)
      # received state diverges us from the database too — later joiners
      # must be able to get it from us (the original editor may be gone)
      |> assign(:blocks_changed?, true)
      |> put_seed_form(root_uid, new_form)
      |> record_synced_snapshot(root_uid, Ops.subtree_snapshot(updated_ops, root_uid))
    else
      {:error, reason} ->
        Logger.warning(
          "BlockField (#{socket.assigns.block_field}) could not apply remote block ops " <>
            "for #{uid}: #{inspect(reason)}"
        )

        socket
    end
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
  # re-materialized seed form (the shell comprehension picks it up from
  # ops.order); a restored CHILD lives inside a mounted parent that owns its
  # form, so the root gets the `replace_form` cascade + remount push — the
  # same path remote-sync applies use (the only sanctioned post-mount form
  # handoff).
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

      socket =
        socket
        |> assign_ops(updated_ops)
        |> assign(:blocks_changed?, true)
        |> put_seed_form(root_uid, new_form)

      socket =
        case location do
          {:root, _at} ->
            socket

          {:child, _parent_uid, _at} ->
            send_update(Block, id: "block-#{root_uid}", event: "replace_form", form: new_form, remount_js: true)
            socket
        end

      {:ok, refresh_live_preview(socket)}
    end
  end

  defp remove_block_from_state(socket, uid) do
    socket
    |> update(:seed_forms, &Map.delete(&1, uid))
    |> apply_block_op({:delete, uid})
    |> refresh_live_preview()
  end

  defp get_form_block_uid(form) do
    block_cs = Changeset.get_assoc(form.source, :block)
    Changeset.get_field(block_cs, :uid)
  end

  # The shells the keyed :for renders: order is the op store's projection,
  # the form is the per-uid mount seed. Fails loudly on a missing seed —
  # every insert path must put a seed before applying its op.
  defp root_shells(root_order, seed_forms) do
    root_order
    |> Enum.with_index()
    |> Enum.map(fn {uid, list_index} -> {uid, Map.fetch!(seed_forms, uid), list_index} end)
  end

  # Recovered blocks were never persisted (the fresh LV process re-initialized
  # from the DB, so anything missing from the render was unsaved) — they enter
  # the op state as inserts, then one reorder restores the pre-disconnect
  # order (sanitized: server-side blocks the client never saw keep their
  # relative order at the end).
  defp apply_recovered_block_ops(socket, recovered_forms, merged_uids) do
    recovered_forms
    |> Enum.reduce(socket, fn {uid, form}, acc ->
      apply_block_op(acc, {:insert, uid, :end, Ops.block_diff_params(form.source)})
    end)
    |> apply_block_op({:reorder, merged_uids})
  end

  # reposition a main block
  def handle_event("reposition", %{"new" => new_idx, "old" => old_idx}, socket) when new_idx == old_idx do
    # same index, no move needed
    {:noreply, socket}
  end

  def handle_event("reposition", %{"uid" => uid, "new" => new_idx, "old" => _old_idx}, socket) do
    socket = apply_block_op(socket, {:move, uid, new_idx})

    # Broadcast the store's order to other users
    if topic = socket.assigns[:blocks_topic] do
      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        topic,
        {:blocks_reordered, %{block_list: socket.assigns.block_ops.order, user_id: socket.assigns.current_user.id}}
      )
    end

    socket
    |> refresh_live_preview()
    |> then(&{:noreply, &1})
  end

  def handle_event("paste_block_at_end", _, socket) do
    {:noreply, paste_root_block(socket, length(socket.assigns.block_ops.order))}
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

  def handle_event("outline_root_reposition", %{"uid" => uid, "new" => new_idx, "old" => _old_idx}, socket) do
    socket = apply_block_op(socket, {:move, uid, new_idx})

    # Broadcast the store's order to other users
    if topic = socket.assigns[:blocks_topic] do
      Phoenix.PubSub.broadcast(
        Brando.pubsub(),
        topic,
        {:blocks_reordered, %{block_list: socket.assigns.block_ops.order, user_id: socket.assigns.current_user.id}}
      )
    end

    socket
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
    module_set = socket.assigns.module_set

    send_update(ModulePicker,
      id: block_picker_id,
      event: :show_module_picker,
      filter: %{parent_id: nil, namespace: module_set},
      module_set: module_set,
      type: :module,
      sequence: length(socket.assigns.block_ops.order) + 1,
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
        # Merge recovered seeds in, then let ONE reorder to the client's
        # pre-disconnect root order set structure — sequence derives from
        # list order at materialization, so no per-form sequence restamp.
        seed_forms = Map.merge(socket.assigns.seed_forms, recovered_forms)
        merged_uids = Enum.filter(root_uids, &Map.has_key?(seed_forms, &1))

        socket
        |> assign(:seed_forms, seed_forms)
        |> apply_recovered_block_ops(recovered_forms, merged_uids)
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
        <div :if={@root_order != []} class="blocks-actions">
          <div class="block-field-dropdown">
            <button
              type="button"
              class="block-field-dropdown-toggle"
              data-ui-dropdown-toggle={"block-field-#{@block_field}-actions-dropdown"}
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
                  }
                >
                  <.icon name="hero-bars-3-bottom-left" /> {gettext("Block outline")}
                </button>
              </li>
              <li class="dropdown-separator"></li>
              <li>
                <button
                  type="button"
                  phx-click="collapse_root_blocks"
                  phx-target={@myself}
                >
                  <.icon name="hero-eye-slash" /> {gettext("Collapse root blocks")}
                </button>
              </li>
              <li>
                <button
                  type="button"
                  phx-click="expand_root_blocks"
                  phx-target={@myself}
                >
                  <.icon name="hero-eye" /> {gettext("Expand root blocks")}
                </button>
              </li>
              <li>
                <button
                  type="button"
                  phx-click="collapse_multi_children"
                  phx-target={@myself}
                >
                  <.icon name="hero-eye-slash" /> {gettext("Collapse multi blocks")}
                </button>
              </li>
              <li>
                <button
                  type="button"
                  phx-click="expand_multi_children"
                  phx-target={@myself}
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
        <%= if @root_order == [] do %>
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
            :for={{uid, entry_block_form, list_index} <- root_shells(@root_order, @seed_forms)}
            :key={uid}
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
          click={JS.push("show_block_picker", target: @myself)}
          modal={@module_picker_id}
          clipboard_meta={@clipboard_meta}
          paste_context={:root}
          paste_event="paste_block_at_end"
          paste_target={@myself}
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

  # The outline reads the op store, not the seed forms — seeds are mount-time
  # snapshots and would show stale children after any post-mount structural
  # change. Materializing (a few ms even at 100+ blocks) gives the outline
  # live structure AND live content (descriptions, active flags).
  defp rebuild_outline_items(socket) do
    ops = socket.assigns.block_ops
    block_module = socket.assigns.block_module
    user_id = socket.assigns.current_user.id

    items =
      Enum.map(ops.order, fn uid ->
        {:ok, params} = Ops.materialize_root(ops, uid)

        socket
        |> materialize_base_struct(uid)
        |> block_module.changeset(params, user_id, true)
        |> Changeset.apply_changes()
        |> Map.fetch!(:block)
        |> Outline.build_outline_item_from_struct()
      end)

    assign(socket, :outline_items, items)
  end

  defp set_root_blocks_collapsed(socket, collapsed) do
    for block_uid <- socket.assigns.block_ops.order do
      send_update(Block, id: "block-#{block_uid}", event: "set_collapsed", collapsed: collapsed)
    end

    socket
  end

  defp set_multi_children_collapsed(socket, collapsed) do
    for {block_uid, form} <- socket.assigns.seed_forms do
      block_cs = Changeset.get_assoc(form.source, :block)
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

    entry_block_form =
      to_change_form(
        block_module,
        entry_block_cs,
        %{sequence: sequence},
        current_user_id
      )

    selector = "[data-block-uid=\"#{new_uid}\"]"

    socket
    |> put_seed_form(new_uid, entry_block_form)
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
