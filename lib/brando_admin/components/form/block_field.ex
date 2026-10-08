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
  gather protocol. After a completed save, `reload_all_blocks/2` re-seeds
  mounted roots through the `replace_form` cascade (fresh db ids), the only
  sanctioned parent→child form handoff after mount. Roots that provably hold
  the saved rows already are skipped.

  ## Multi-user editing: a replica of the edit session

  With a saved entry open, the store is a replica of the entry's
  `Brando.EditSession` (see `BlockField.Replica`). Every op this editor
  applies is also cast to the session, which orders it, gives it a revision
  and broadcasts it; other editors' ops arrive the same way and are applied
  with the same reducer, so all editors converge on one order. Editors no
  longer exchange snapshots, and a joiner gets the session's current state,
  unsaved work included, instead of asking the others for it.

  Another editor's op refreshes the affected root through the
  `replace_form` cascade, coalesced per root. A keystroke is one field
  (`{:set_field, ...}`), so two editors can work in one block: a root this
  editor is in is refreshed too, without re-booting the focused widget, and
  once more when they leave the field (`@local_focus`). New and moved blocks
  name their place with fractional keys (`Ops.keyed/2`).

  Save, live preview and recovery copies read the session's state, and a
  save hands the saved rows back (`EditSession.rebase/4`) so every replica
  continues from them. If the session dies, the replica joins a new one
  seeded with its own state and casts its unconfirmed ops again.

  ## Restorable bin (delete undo)

  Every local delete stashes an `Ops.bin_snapshot/2` in `@block_bin` before
  the delete op runs; an undo toast offers LIFO restore. Restoring replays
  the snapshot into the store (a `{:restore, snapshot}` op), then re-mounts a
  root from its re-materialized seed form or hands a child's root the
  `replace_form` cascade. The op reaches the other editors like any other.
  The bin clears on save — the save deletes the underlying rows, so stashed
  db ids go stale.
  """
  use BrandoAdmin, :live_component
  use Gettext, backend: Brando.Gettext

  import Ecto.Query, only: [from: 2]

  alias Brando.Content.Blocks, as: ContentBlocks
  alias Brando.Content.BlockSlots
  alias Brando.Content.BlockSlots.Lifecycle, as: CollectionLifecycle
  alias Brando.EditSession
  alias BrandoAdmin.Components.AIAction
  alias BrandoAdmin.Components.Form.Block
  alias BrandoAdmin.Components.Form.BlockField.ModulePicker
  alias BrandoAdmin.Components.Form.BlockField.Ops
  alias BrandoAdmin.Components.Form.BlockField.Outline
  alias BrandoAdmin.Components.Form.BlockField.Replica
  alias Ecto.Changeset
  alias Phoenix.PubSub

  require Logger

  def mount(socket) do
    {:ok,
     assign(socket,
       outline_items: [],
       open_slot_uid: nil,
       slot_title: nil,
       note_observers: %{},
       live_preview_active?: false,
       live_preview_cache_key: nil
     )}
  end

  @structural_ops [:insert, :insert_child, :move, :reorder, :reorder_children, :move_to_parent, :remap_slot, :delete]

  # A synchronized translation's structure follows its source: this editor's
  # structural events are refused before they touch the store, the bin or the
  # other editors. Content edits (`{:update, …}` ops) pass.
  @locked_events ~w(create_footnote duplicate_block paste_block paste_child_block delete_block
                    insert_extracted_child insert_block insert_container insert_fragment remap_region)

  def update(%{event: event}, %{assigns: %{source_locked: true}} = socket) when event in @locked_events,
    do: {:ok, refuse_structure(socket, event)}

  def update(%{event: "block_op", op: op}, %{assigns: %{source_locked: true}} = socket)
      when elem(op, 0) in @structural_ops,
      do: {:ok, refuse_structure(socket, elem(op, 0))}

  def update(
        %{event: "field_note_action", action: "delete_unused_collection"},
        %{assigns: %{source_locked: true}} = socket
      ),
      do: {:ok, refuse_structure(socket, "delete_unused_collection")}

  def update(%{event: "close_slot"}, socket), do: {:ok, assign(socket, :open_slot_uid, nil)}

  def update(%{event: "inspect_field_notes", field: field, html: html, reply_to: reply_to}, socket) do
    if Map.has_key?(socket.assigns.footnote_fields, field) do
      {:ok,
       socket
       |> update(:note_observers, &Map.put(&1, field, %{html: html, reply_to: reply_to}))
       |> notify_note_observers()}
    else
      {:ok, socket}
    end
  end

  def update(
        %{event: "field_note_action", field: field, html: html, uid: uid, action: action, input_id: input_id},
        socket
      ) do
    unused = CollectionLifecycle.unused_notes(field_note_slots(socket), field, html)

    if Map.has_key?(socket.assigns.footnote_fields, field) && Enum.any?(unused, &(&1.uid == uid)) do
      case action do
        "open_unused_collection" ->
          {:ok, assign(socket, open_slot_uid: uid, slot_title: gettext("Footnote"))}

        "restore_note_reference" ->
          {:ok, push_event(socket, "b:tiptap:insert_footnote:#{input_id}", %{uid: uid, restore: true})}

        "delete_unused_collection" ->
          update(%{event: "delete_block", uid: uid}, assign(socket, :open_slot_uid, nil))

        _ ->
          {:ok, socket}
      end
    else
      {:ok, socket}
    end
  end

  def update(%{event: "region_remap_targets", owner_uid: owner_uid, uid: uid, reply_to: reply_to}, socket) do
    targets =
      case collection_owner(socket, owner_uid) do
        {:ok, owner} ->
          owner
          |> CollectionLifecycle.remap_targets(CollectionLifecycle.definitions(owner), uid)
          |> Enum.map(&{&1.description || &1.name, &1.name})

        _ ->
          []
      end

    send_update(reply_to, event: "region_remap_targets", uid: uid, targets: targets)
    {:ok, socket}
  end

  def update(%{event: "remap_region", owner_uid: owner_uid, uid: uid, name: name, reply_to: reply_to}, socket) do
    with {:ok, owner} <- collection_owner(socket, owner_uid),
         {:ok, destination_uid, params} <-
           CollectionLifecycle.remap(owner, CollectionLifecycle.definitions(owner), uid, name),
         {:ok, _} <- Ops.apply_op(socket.assigns.block_ops, {:remap_slot, uid, destination_uid, params}) do
      root_uid = Ops.root_of(socket.assigns.block_ops, owner_uid)

      socket =
        socket
        |> apply_block_op({:remap_slot, uid, destination_uid, params})
        |> replace_root_from_store(root_uid)
        |> refresh_live_preview()

      send_update(reply_to, event: "region_remapped")
      {:ok, socket}
    else
      _ ->
        send_update(reply_to, event: "region_remap_failed")
        {:ok, socket}
    end
  end

  def update(%{event: "create_footnote", field: field, params: params}, socket) do
    with %{enabled: true, module_set: set} <- socket.assigns.footnote_fields[field],
         [module | _] <- BlockSlots.modules(set) do
      uid = Brando.Utils.generate_uid()
      user_id = socket.assigns.current_user.id
      source = socket.assigns.block_module
      child = build_block({module.library_origin, module.id}, user_id, nil, source, :module)
      slot = BlockSlots.build(:footnote, to_string(field), set, source, user_id, uid)
      slot = Changeset.put_assoc(slot, :children, [child])
      sequence = length(socket.assigns.root_order)

      entry_block_cs =
        source
        |> struct(%{})
        |> Changeset.change(%{entry_id: socket.assigns.entry.id, sequence: sequence})
        |> Changeset.put_assoc(:block, slot)
        |> Map.put(:action, :insert)

      form = to_form(entry_block_cs, as: "entry_block", id: "entry_block_form-#{uid}")

      socket
      |> put_seed_form(uid, form)
      |> apply_block_op({:insert, uid, sequence, Ops.block_diff_params(entry_block_cs)})
      |> assign(open_slot_uid: uid, slot_title: gettext("Footnote"))
      |> push_event("b:tiptap:insert_footnote:#{params["tiptap_id"]}", %{uid: uid})
      |> then(&{:ok, &1})
    else
      _ ->
        {:ok,
         put_flash(
           socket,
           :error,
           gettext("This field’s footnote module set has no suitable modules. Add a Text module to it first.")
         )}
    end
  end

  def update(%{event: "open_footnote", field: field, params: %{"uid" => uid}}, socket) do
    slot =
      case socket.assigns.seed_forms[uid] do
        nil -> nil
        form -> Changeset.get_assoc(form.source, :block, :struct)
      end

    if slot && slot.slot_kind == :footnote && slot.slot_name == to_string(field) do
      {:ok, assign(socket, open_slot_uid: uid, slot_title: gettext("Footnote"))}
    else
      {:ok, put_flash(socket, :error, gettext("This footnote could not be found in this field."))}
    end
  end

  # A revision loaded as a working copy (the revisions drawer): its blocks,
  # as changes on top of the rows the entry has now, so a save writes them.
  # The field leaves the edit session first (`EditSession.detach/2`): what
  # it shows now is not what the others edit, and the unsaved work the
  # session holds is what the working copy replaced.
  def update(%{event: "load_working_copy", entry_blocks: revision_blocks}, socket) do
    socket = detach_session(socket)
    rows = socket.assigns.entry_blocks || []
    {:ok, restore_draft(socket, working_copy_changesets(socket, revision_blocks, rows), rows)}
  end

  def update(%{event: "restore_draft", changesets: changesets, entry_blocks: originals} = message, socket) do
    if Map.get(message, :source) == :translation and joined_with_work?(socket) do
      # A synchronized translation's pending version, loaded by an editor who
      # joined an edit session that already holds unsaved work: the editor
      # who opened it first loaded the version, and the work is on top of it.
      {:ok, socket}
    else
      {:ok, restore_draft(socket, changesets, originals)}
    end
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
    clipboard = read_clipboard(user_id)

    if clipboard do
      block_cs = create_duplicate_from_clipboard(clipboard, user_id, socket.assigns.block_module)
      send_to_ref(parent_ref, %{event: "insert_pasted_block", block_cs: block_cs, sequence: sequence})
    end

    {:ok, socket}
  end

  def update(%{event: "delete_block", uid: uid}, socket) do
    {:ok, socket |> stash_in_bin(uid) |> remove_block_from_state(uid)}
  end

  # blocks (any level) emit their content/structural ops directly — see
  # Block.emit_block_op/2. Forms never travel up; seed forms are only read
  # at first mount.
  # Child deletes pass through the bin first — the op tears the subtree out
  # of the store, so the undo snapshot must be captured here.
  def update(%{event: "block_op", op: {:delete, uid} = op}, socket) do
    {:ok,
     socket
     |> stash_in_bin(uid)
     |> apply_block_op(op)}
  end

  def update(%{event: "block_op", op: op}, socket) do
    {:ok, apply_block_op(socket, op)}
  end

  # Outline: relay extracted child to target parent.
  #
  # The child's changeset is rebuilt HERE, from the op store, rather than
  # accepted from the source parent — that parent only holds a mount-time seed
  # form, so a moved child used to arrive with its original content and wipe the
  # user's edits when the target re-registered its diff.
  def update(
        %{event: "insert_extracted_child", target_parent_uid: target_uid, child_uid: uid, sequence: seq},
        socket
      ) do
    # `outline_reposition` already proved this materializes before it told the
    # source parent to let go, so a failure here means the store changed
    # underneath us. The source has by now dropped the child from its own
    # `block_list`, and `rebuild_outline_items/1` only reflects the canonical
    # store — so simply returning would leave the block invisible on the canvas
    # while still alive server-side. Reload instead: the store is authoritative
    # and re-mounting the roots from it restores a consistent view.
    case build_child_changeset(socket, uid) do
      {:ok, cs} ->
        send_update(Block,
          id: "block-#{target_uid}",
          event: "insert_pasted_block",
          block_cs: cs,
          sequence: seq
        )

        {:ok, rebuild_outline_items(socket)}

      {:error, reason} ->
        require Logger

        Logger.error("""
        [BlockField] cross-parent move of #{inspect(uid)} failed AFTER the source parent \
        released it: #{inspect(reason)}. Reloading blocks from the op store to avoid \
        stranding it off-canvas.
        """)

        {:ok, socket |> reload_all_blocks() |> rebuild_outline_items()}
    end
  end

  # INSERT ROOT BLOCK
  def update(%{event: "insert_block", sequence: sequence, module_id: module_id}, socket) do
    sequence = (is_integer(sequence) && sequence) || String.to_integer(sequence)
    {:ok, insert_root_module(socket, module_id, sequence)}
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

  def update(%{event: "capture_draft", capture_id: id, reply_to: target, forms: forms}, socket) do
    alias Brando.Drafts.Params

    # A recovery copy holds what the session holds: this editor's work and
    # whatever the others' replicas have not shown here yet.
    ops = session_ops(socket)
    cache = socket.assigns[:draft_snapshots] || %{}

    # A root's snapshot is a pure function of its saved row, its store state
    # and the browser values overlaid on its subtree, so an unchanged key
    # reuses the last capture's result. Rebuilding all of them cost ~80 ms of
    # the LiveView process per capture at 115 roots; usually one has changed.
    {roots, cache} =
      Enum.map_reduce(ops.order, %{}, fn uid, acc ->
        {:ok, params} = Ops.materialize_root(ops, uid)
        base = materialize_base_struct(socket, uid)
        key = {base, params, Map.take(forms, [uid | Ops.descendants(ops, uid)])}

        snapshot =
          case cache do
            %{^uid => {^key, snapshot}} ->
              snapshot

            _ ->
              module = socket.assigns.block_module
              full = module.changeset(base, params, socket.assigns.current_user.id, true) |> Params.snapshot()
              full = Map.update!(full, "block", &Params.overlay_block(&1, forms))
              module.changeset(base, full, socket.assigns.current_user.id, true) |> Params.snapshot()
          end

        {snapshot, Map.put(acc, uid, {key, snapshot})}
      end)

    send_update(target, event: "draft_part", capture_id: id, kind: :block, field: socket.assigns.block_field, data: roots)
    {:ok, assign(socket, :draft_snapshots, cache)}
  rescue
    _ ->
      send_update(target, event: "draft_timeout", capture_id: id)
      {:ok, socket}
  end

  # Save, live preview and share all read the op store — the store is
  # commit-complete (every commit point emits a diff op), so ONE
  # materialization pass builds all root changesets for any tag. The old
  # recursive fetch/provide gather across the component tree is gone.
  def update(%{event: "fetch_root_blocks", tag: tag}, socket) do
    # The session's state, not the replica's: it holds every op this editor
    # cast before asking (a process's messages arrive in order) and every op
    # the others' did. A save marks the revision it read, so its rebase can
    # replay what arrives while it runs.
    {ops, socket} = session_ops_for(socket, tag)
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

  def update(%{event: "reload_all_blocks"} = msg, socket) do
    {:ok, reload_all_blocks(socket, Map.get(msg, :scope, :all))}
  end

  # === Edit session ===

  # Everything the session broadcasts for this field (routed by
  # `BrandoAdmin.LiveView.Form.Hooks`): ops, rebases, rejections.
  def update(%{event: "edit_session", message: message}, socket) do
    {:ok, handle_session_message(socket, message)}
  end

  # The session process died: join a new one seeded with this replica.
  def update(%{event: "edit_session_down"}, socket) do
    {:ok, rejoin_session(socket)}
  end

  # Coalesced refresh of the roots other editors changed.
  def update(%{event: "flush_remote_refresh"}, socket) do
    {:ok, flush_remote_refresh(assign(socket, :remote_refresh_scheduled?, false))}
  end

  # Where this editor works: a block (its root's uid is kept) and a field in
  # it, or nil. Other editors' changes reach a root while it is in use, but
  # the input with the focus keeps what is being typed into it; when the
  # editor moves to another field or leaves, the root is shown once more so
  # that input catches up too.
  def update(%{event: "local_focus", uid: uid} = message, socket) do
    ops = socket.assigns.block_ops
    root = if uid && Ops.known?(ops, uid), do: Ops.root_of(ops, uid)
    field = Map.get(message, :field)
    previous = {socket.assigns[:local_focus], socket.assigns[:local_focus_field]}
    socket = assign(socket, local_focus: root, local_focus_field: field)

    case previous do
      {previous_root, previous_field}
      when not is_nil(previous_root) and {previous_root, previous_field} != {root, field} ->
        if MapSet.member?(socket.assigns.deferred_roots, previous_root),
          do:
            {:ok,
             socket
             |> update(:deferred_roots, &MapSet.delete(&1, previous_root))
             |> refresh_roots([previous_root], :force)},
          else: {:ok, socket}

      _ ->
        {:ok, socket}
    end
  end

  def update(assigns, socket) do
    # On the first update no block has mounted yet: a session state shown
    # now only needs seed forms.
    mounted? = !!socket.assigns[:blocks_initialized]

    socket
    |> assign(assigns)
    |> assign_new(:hidden, fn -> false end)
    |> assign_new(:focus, fn -> nil end)
    |> assign_new(:session_detached?, fn -> false end)
    |> initialize_blocks(assigns)
    |> maybe_join_session(mounted?)
    |> assign_module_set()
    |> assign_new(:templates, fn -> [] end)
    |> maybe_assign_starting_modules()
    |> then(&{:ok, &1})
  end

  defp initialize_blocks(%{assigns: %{blocks_initialized: true}} = socket, _assigns), do: socket

  defp initialize_blocks(socket, assigns) do
    block_module = assigns.block_module
    user_id = assigns.current_user.id
    entry_blocks = assigns.entry_blocks || []

    entry_blocks_forms = Enum.map(entry_blocks, &to_change_form(block_module, &1, %{}, user_id))

    socket
    |> assign(:seed_forms, Map.new(entry_blocks_forms, &{get_form_block_uid(&1), &1}))
    |> assign_ops(Ops.from_entry_blocks(entry_blocks))
    # Bare id, not a selector — consumed by `data-ui-modal-show`.
    |> assign(:module_picker_id, "block-field-#{assigns.block_field}-module-picker")
    |> assign_clipboard_meta(read_clipboard(user_id))
    |> assign(:block_bin, [])
    |> assign(:blocks_changed?, false)
    |> assign(:edit_session, nil)
    |> assign(:local_focus, nil)
    |> assign(:local_focus_field, nil)
    |> assign(:refreshed_at, %{})
    |> assign(:deferred_roots, MapSet.new())
    |> assign(:remote_refresh, MapSet.new())
    |> assign(:remote_refresh_scheduled?, false)
    |> assign(:remote_preview_dirty?, false)
    |> assign(:rescue_standby, %{})
    |> assign(:blocks_initialized, true)
    |> assign(:footnote_fields, assigns.opts[:footnote_fields] || %{})
    |> assign(:note_collection?, !!assigns.opts[:footnote_fields])
    |> assign(:assistant?, assistant?(assigns))
    |> assign(:manages_templates?, manages_templates?(assigns))
    |> assign_new(:source_locked, fn -> false end)
    |> assign_new(:source_url, fn -> nil end)
  end

  ## Edit session
  #
  # The store as a replica of `Brando.EditSession` (see `BlockField.Replica`).

  # Join once the field has a saved entry, in a connected process. A create
  # form has no entry id yet and joins when its first save lands the entry
  # here. A revision being previewed (`session_detached?`) does not join: what
  # it shows is not what the others edit.
  defp maybe_join_session(%{assigns: %{edit_session: nil, entry: %{id: id}}} = socket, mounted?)
       when not is_nil(id) do
    cond do
      not connected?(socket) -> socket
      socket.assigns.session_detached? -> assign(socket, :edit_session, :detached)
      true -> join_session(socket, mounted?: mounted?)
    end
  end

  defp maybe_join_session(socket, _mounted?), do: socket

  defp join_session(socket, opts) do
    %{entry: entry, block_field: field, current_user: user} = socket.assigns
    ref = EditSession.ref_for(entry)
    subscribe_session(ref)
    base = Ops.from_entry_blocks(socket.assigns.entry_blocks || [])
    # What this editor shows. On a fresh open that is the rows; a replica
    # coming back to a replaced session holds unsaved work, which the
    # session carries onto its state (a fresh joiner may have seeded it from
    # the database first).
    held = Keyword.get(opts, :held, base)
    join_opts = [user_id: user.id, read_only: not may_update?(socket)]

    {socket, result} =
      case EditSession.join(ref, field, {base, held}, [rebase: Keyword.get(opts, :rebase, false)] ++ join_opts) do
        {:error, :base_mismatch} ->
          # The rows this editor loaded are not the ones the session is built
          # on. Read them again: if they still differ, they are newer, written
          # outside the session, and the session moves onto them, with what
          # this editor holds carried over (it was built on the old rows).
          socket = reload_entry_blocks(socket)
          new_base = Ops.from_entry_blocks(socket.assigns.entry_blocks)

          {socket, EditSession.join(ref, field, {new_base, held}, [rebase: true, held_base: base] ++ join_opts)}

        result ->
          {socket, result}
      end

    case result do
      {:ok, info} ->
        # Work only this editor held that the session could not take: blocks
        # another write removed while it was away. It brings them back itself.
        rescues = Map.get(info, :rescues, [])
        payloads = rescue_payloads(socket, rescues, info.state, MapSet.new(Ops.edited(socket.assigns.block_ops)))

        socket
        |> assign(:session_base, Ops.from_entry_blocks(socket.assigns.entry_blocks || []))
        |> adopt_session(ref, info, opts)
        |> rescue_own(rescues, payloads)
        |> announce_join()

      {:error, reason} ->
        Logger.warning("BlockField (#{field}) could not join its edit session: #{inspect(reason)}")
        assign(socket, :edit_session, :failed)
    end
  end

  defp adopt_session(socket, ref, info, opts) do
    monitor = Process.monitor(info.session)
    # The LiveView receives the :DOWN; the hooks route it here by this key.
    Process.put({:brando_edit_session_monitor, monitor}, socket.assigns.id)

    # What this editor held, its unconfirmed ops included, went to the
    # session with the join: nothing is cast again.
    replica = %{Replica.new(ref, info, monitor) | read_only: not may_update?(socket)}

    socket
    |> assign(:edit_session, replica)
    |> show_state(Replica.displayed(replica), :all, mounted?: Keyword.get(opts, :mounted?, true))
  end

  defp may_update?(%{assigns: %{entry: entry, current_user: user}}) do
    Brando.Authorization.Boundary.authorize(user, :update, entry) == :ok
  rescue
    _ -> false
  end

  # One subscription per LiveView process, however many block fields join.
  defp subscribe_session(%{topic: topic}) do
    unless Process.get({:brando_edit_session_topic, topic}) do
      PubSub.subscribe(Brando.pubsub(), topic)
      Process.put({:brando_edit_session_topic, topic}, true)
    end
  end

  # Other editors replay unsaved entry fields and their focus for a joiner
  # (see `BrandoAdmin.LiveView.Form.Hooks`). Blocks need no replay: the
  # session's state already holds them.
  defp announce_join(socket) do
    entry = socket.assigns.entry

    PubSub.broadcast(
      Brando.pubsub(),
      Brando.Tenant.Topic.entry("field_sync", entry.__struct__, entry.id),
      {:editor_joined, %{user_id: socket.assigns.current_user.id}}
    )

    socket
  end

  # In a shared session a new or moved block names its place by the keys of
  # the neighbours it was put between (`Ops.keyed/2`), so it lands there
  # whatever the others did first.
  # A field op carries the revision the editor saw.
  defp keyed(%{assigns: %{edit_session: %Replica{rev: rev}}}, {:set_field, uid, path, value, nil}),
    do: {:set_field, uid, path, value, rev}

  defp keyed(%{assigns: %{edit_session: %Replica{rev: rev}}}, {:set_fields, uid, changes, nil}),
    do: {:set_fields, uid, changes, rev}

  defp keyed(%{assigns: %{edit_session: %Replica{}, block_ops: ops}}, op), do: Ops.keyed(ops, op)
  defp keyed(_socket, op), do: op

  # Someone who may not change the entry follows the others but sends nothing.
  defp submit_to_session(%{assigns: %{edit_session: %Replica{read_only: true}}} = socket, _op), do: socket

  defp submit_to_session(%{assigns: %{edit_session: %Replica{session: session} = replica}} = socket, op) do
    {replica, seq} = Replica.local(replica, op)
    EditSession.submit(session, socket.assigns.block_field, op, seq)
    assign(socket, :edit_session, replica)
  end

  defp submit_to_session(socket, _op), do: socket

  defp handle_session_message(%{assigns: %{edit_session: %Replica{} = replica}} = socket, %{kind: :op} = message) do
    case Replica.receive_op(replica, message) do
      {:own, replica} ->
        assign(socket, :edit_session, replica)

      {:remote, replica, displayed} ->
        socket
        |> assign(:edit_session, replica)
        |> show_state(displayed, hint_uids(message.op))

      :stale ->
        socket

      :resync ->
        resync_session(socket)
    end
  end

  defp handle_session_message(%{assigns: %{edit_session: %Replica{} = replica}} = socket, %{kind: :rejected} = message) do
    case Replica.receive_rejected(replica, message) do
      {replica, displayed, op} ->
        socket
        |> assign(:edit_session, replica)
        |> show_state(displayed, :all)
        |> report_rejection(op, message.reason)

      :stale ->
        socket
    end
  end

  defp handle_session_message(%{assigns: %{edit_session: %Replica{} = replica}} = socket, %{kind: :rebase} = message) do
    if Replica.newer?(replica, message) do
      apply_rebase(socket, replica, message)
    else
      socket
    end
  end

  # The editor asked to bring a group back did not: this one is asked now.
  defp handle_session_message(%{assigns: %{edit_session: %Replica{}}} = socket, %{kind: :rescue} = message) do
    if message.rescuer == self(),
      do: rescue_group(socket, message.group, Map.get(socket.assigns.rescue_standby, message.group)),
      else: socket
  end

  # How a rescue went, told to the editors whose work it was and, for work
  # of an editor who has left, to those who were here when it was removed:
  # not to one who joined after and never saw it.
  defp handle_session_message(socket, %{kind: :rescued} = message) do
    socket = update(socket, :rescue_standby, &Map.delete(&1, message.group))
    here? = self() in Map.get(message, :present, [])
    tell_rescued(message.ok?, self() in message.owners, message.orphan? and here?)
    socket
  end

  defp handle_session_message(socket, _message), do: socket

  # Someone saved, or the entry was written outside the editor: the session
  # moved onto new rows. Read them unless they are the ones already here,
  # then show the session's state on top of them.
  defp apply_rebase(socket, replica, message) do
    old_rows = rows_by_uid(socket.assigns.entry_blocks)
    # Blocks with unsaved work that the new rows no longer have: taken from
    # what this editor showed, before it moves on, to bring back if the
    # session asks it to (`rescues`).
    rescues = Map.get(message, :rescues, [])
    payloads = rescue_payloads(socket, rescues, message.state, Map.get(message, :worked, MapSet.new()))

    # The rows were written (by another editor's save, or outside the
    # editor): read them, as their content can change while their ids and
    # order stay. A join that only carried work onto the state wrote none.
    socket =
      if message.reason == :joined and
           Ops.signature(message.base) == Ops.signature(Ops.from_entry_blocks(socket.assigns.entry_blocks || [])),
         do: socket,
         else: reload_entry_blocks(socket)

    new_rows = rows_by_uid(socket.assigns.entry_blocks)
    rewritten = for {uid, row} <- new_rows, Map.has_key?(old_rows, uid), old_rows[uid] != row, do: uid
    {replica, displayed} = Replica.reset(replica, message)

    socket
    |> assign(:edit_session, replica)
    |> assign(:session_base, message.base)
    |> assign(:block_bin, [])
    |> show_state(displayed, :all, also: rewritten, base: message.base)
    |> perform_rescues(rescues, payloads)
  end

  defp rows_by_uid(entry_blocks), do: Map.new(entry_blocks || [], &{&1.block.uid, &1})

  # Unsaved work on a block that another write removed cannot be carried
  # onto the new rows. It comes back as a new block, with its changes, so
  # nothing is lost: the session names one editor per removed block
  # (`group`, the top-most block the write removed) to bring back every
  # block with work under it, in one copy (`Brando.EditSession`). Every
  # editor takes what it would bring back from what it showed, before it
  # moves on, in case the session asks it later. The removed rows may live
  # on unattached, so the copy takes new uids, derived from the old ones.
  defp rescue_payloads(socket, rescues, %Ops{} = new, worked) do
    old = socket.assigns.block_ops
    Map.new(rescues, &{&1.group, rescue_payload(socket, old, new, &1, worked)})
  end

  # What brings back the blocks `uids` under `group`: under the nearest
  # ancestor of `group` that is still there, or as a root. Removed blocks
  # this editor's session worked in come back whole (a child added to a
  # container brings the container back); the others around them come back
  # as `-kept` shells holding only the way to them: a child block is made
  # for its parent (a multi module's entry, a container's child) and would
  # not read, or render, as a root of its own.
  defp rescue_payload(socket, %Ops{} = old, %Ops{} = new, %{group: group, uids: uids, kept: kept}, worked) do
    whole =
      uids
      |> Enum.filter(&Ops.known?(old, &1))
      |> Enum.map(fn uid ->
        # the removed blocks above it, up to and with `group`
        {below, top} = old |> ancestors(uid) |> Enum.split_while(&(&1 != group))

        (below ++ Enum.take(top, 1))
        |> Enum.take_while(&MapSet.member?(worked, &1))
        |> Enum.reduce(uid, fn ancestor, _below -> ancestor end)
      end)
      |> Enum.uniq()

    whole = Enum.reject(whole, fn uid -> Enum.any?(ancestors(old, uid), &(&1 in whole)) end)

    with true <- whole != [] and Ops.known?(old, group),
         %{} = block <- rescue_tree(socket, old, group, whole) do
      surviving = old |> ancestors(group) |> Enum.find(&Ops.known?(new, &1))
      place_rescued(socket, old, group, block, surviving, kept)
    else
      _ -> nil
    end
  rescue
    error ->
      Logger.error("BlockField could not keep a removed block's unsaved work: " <> Exception.message(error))
      nil
  end

  defp rescue_tree(socket, old, uid, whole) do
    cond do
      uid in whole ->
        rescued_block(socket, old, uid)

      block = rescued_block(socket, old, uid) ->
        children =
          old.child_order
          |> Map.get(uid, [])
          |> Enum.filter(fn child -> child in whole or Enum.any?(whole, &(child in ancestors(old, &1))) end)
          |> Enum.map(&rescue_tree(socket, old, &1, whole))
          |> Enum.reject(&is_nil/1)

        Map.put(block, "children", children)

      true ->
        nil
    end
  end

  defp place_rescued(_socket, _old, _group, block, parent, kept) when is_binary(parent),
    do: {:child, parent, block, kept}

  defp place_rescued(socket, old, group, block, nil, kept) do
    with %{} = entry_block <- rescued_params(socket, old, group), do: {:root, Map.put(entry_block, "block", block), kept}
  end

  defp rescued_block(socket, old, uid) do
    case rescued_params(socket, old, uid) do
      %{"block" => block} -> block
      _ -> nil
    end
  end

  defp ancestors(ops, uid) do
    case Map.get(ops.parents, uid) do
      nil -> []
      parent -> [parent | ancestors(ops, parent)]
    end
  end

  # The session asked this editor to bring back the groups it names: the
  # others keep theirs, in case it asks them later.
  defp perform_rescues(socket, rescues, payloads) do
    Enum.reduce(rescues, socket, fn %{group: group, rescuer: rescuer}, socket ->
      if rescuer == self(),
        do: rescue_group(socket, group, payloads[group]),
        else: update(socket, :rescue_standby, &Map.put(&1, group, payloads[group]))
    end)
  end

  # The insert is cast to the session first; the session checks its state
  # for the copy when it hears this editor is done (`EditSession.rescued/3`).
  defp rescue_group(%{assigns: %{edit_session: %Replica{session: session}}} = socket, group, payload) do
    {socket, _inserted?} = reinsert_payload(socket, payload)
    EditSession.rescued(session, socket.assigns.block_field, group)
    update(socket, :rescue_standby, &Map.delete(&1, group))
  end

  defp rescue_group(socket, _group, _payload), do: socket

  defp reinsert_payload(socket, nil), do: {socket, false}

  # The copy takes the uid the session chose for this rescue. Already there,
  # it is an insert of an editor asked before, landing late: not made twice.
  defp reinsert_payload(socket, payload) do
    if Ops.known?(socket.assigns.block_ops, elem(payload, tuple_size(payload) - 1)),
      do: {socket, true},
      else: do_reinsert_payload(socket, payload)
  end

  defp do_reinsert_payload(socket, payload) do
    {socket, uid} = reinsert(socket, payload)

    if Ops.known?(socket.assigns.block_ops, uid),
      do: {socket, true},
      else: {update(socket, :seed_forms, &Map.delete(&1, uid)), false}
  end

  defp rescue_own(socket, rescues, payloads) do
    Enum.reduce(rescues, socket, fn %{group: group}, socket ->
      {socket, ok?} = reinsert_payload(socket, payloads[group])
      tell_rescued(ok?, true, false)
      socket
    end)
  end

  # Every editor hears how the session's rescue went: one whose work it
  # was, and everyone when the work was an editor's who has left.
  defp tell_rescued(true, own?, orphan?) do
    if own?,
      do:
        send(
          self(),
          {:toast,
           gettext(
             "A block you had unsaved changes in was removed by another save. It is back at the end, as a new block, with your changes."
           )}
        )

    if orphan?,
      do:
        send(
          self(),
          {:toast,
           gettext(
             "Unsaved changes an editor who has left made in a block another save removed are back at the end, as a new block."
           )}
        )
  end

  defp tell_rescued(false, own?, orphan?) do
    if own?,
      do:
        send(
          self(),
          {:toast,
           gettext("A block you had unsaved changes in was removed by another save, and could not be brought back.")}
        )

    if orphan?,
      do:
        send(
          self(),
          {:toast,
           gettext(
             "Unsaved changes an editor who has left made in a block another save removed could not be brought back."
           )}
        )
  end

  defp rescued_params(socket, old, uid) do
    params =
      if uid in old.order do
        socket |> materialized_form(old, uid) |> Map.fetch!(:source) |> Brando.Drafts.Params.snapshot()
      else
        {:ok, child} = build_child_changeset(socket, uid)
        %{"block" => Brando.Drafts.Params.snapshot(child)}
      end

    strip_row_ids(params)
  rescue
    error ->
      Logger.error("BlockField could not keep a removed block's unsaved work: " <> Exception.message(error))
      nil
  end

  # A block brought back as new owns none of the old rows.
  @row_keys ~w(id entry_id block_id parent_id)
  defp strip_row_ids(%{} = params) when not is_struct(params),
    do: params |> Map.drop(@row_keys) |> Map.new(fn {key, value} -> {key, strip_row_ids(value)} end)

  defp strip_row_ids(list) when is_list(list), do: Enum.map(list, &strip_row_ids/1)
  defp strip_row_ids(value), do: value

  # The block comes back under a new uid, the one the session chose
  # (`<uid>-kept`, or `-kept-2` and on when that is taken): the removed rows
  # can still hold the old one. The blocks under it take the same suffix. A
  # copy that is already there is not made again (`reinsert_payload/2`): a
  # rescue brings a group back once. Its refs, whose uids are unique as
  # well, get new ones. Nothing else changes: a `"uid"` inside a ref's data
  # is the data's own.
  defp rename_copy(%{"uid" => uid} = block, kept), do: rename_block(block, String.replace_prefix(kept, uid, ""))

  defp rename_block(%{} = block, suffix) do
    block
    |> Map.update("uid", nil, &(&1 <> suffix))
    |> Map.update("refs", [], fn refs -> Enum.map(refs, &Map.put(&1, "uid", Brando.Utils.generate_uid())) end)
    |> Map.update("children", [], fn children -> Enum.map(children, &rename_block(&1, suffix)) end)
  end

  defp reinsert(socket, {:root, params, kept}) do
    params = Map.update!(params, "block", &rename_copy(&1, kept))
    uid = params["block"]["uid"]

    form =
      socket
      |> materialize_base_struct(uid)
      |> socket.assigns.block_module.changeset(params, socket.assigns.current_user.id, true)
      |> without_params()
      |> to_form(as: "entry_block", id: "entry_block_form-#{uid}")

    socket =
      socket
      |> put_seed_form(uid, form)
      |> apply_block_op({:insert, uid, :end, params}, :replay)

    {socket, uid}
  end

  # Under a block that is still there: its root shows it once it has it.
  defp reinsert(socket, {:child, parent, block, kept}) do
    block = rename_copy(block, kept)
    uid = block["uid"]
    socket = apply_block_op(socket, {:insert_child, parent, uid, :end, block}, :replay)

    socket =
      if Ops.known?(socket.assigns.block_ops, uid),
        do: refresh_roots(socket, [Ops.root_of(socket.assigns.block_ops, uid)]),
        else: socket

    {socket, uid}
  end

  # An op turned away because another editor removed its block.
  defp report_rejection(socket, op, {:unknown_uid, _uid})
       when elem(op, 0) in [:update, :set_field, :set_fields, :insert_child, :reorder_children] do
    send(self(), {:toast, gettext("Another editor removed the block you were changing.")})
    socket
  end

  defp report_rejection(socket, _op, _reason), do: socket

  # A revision went missing, or a broadcast op did not apply: take the
  # session's state as it is.
  defp resync_session(%{assigns: %{edit_session: %Replica{session: session} = replica}} = socket) do
    case EditSession.fetch(session, socket.assigns.block_field) do
      {:ok, info} ->
        {replica, displayed} = Replica.reset(replica, info)

        socket
        |> assign(:edit_session, replica)
        |> show_state(displayed, :all)

      {:error, _} ->
        rejoin_session(socket)
    end
  end

  # The session died. Join a new one: the first replica back seeds it with
  # its own state, the others take that state and cast the ops it never
  # confirmed again. Nothing in a replica is lost, and recovery copies stay
  # the safety net if every editor went away too.
  defp rejoin_session(%{assigns: %{edit_session: %Replica{} = replica}} = socket) do
    Process.delete({:brando_edit_session_monitor, replica.monitor})

    socket
    |> assign(:edit_session, nil)
    |> join_session(held: socket.assigns.block_ops)
  end

  defp rejoin_session(socket), do: socket

  defp session_ops(%{assigns: %{edit_session: %Replica{session: session}}} = socket) do
    case EditSession.fetch(session, socket.assigns.block_field) do
      {:ok, %{state: %Ops{} = state}} -> state
      _ -> socket.assigns.block_ops
    end
  end

  defp session_ops(socket), do: socket.assigns.block_ops

  defp session_ops_for(%{assigns: %{edit_session: %Replica{session: session}}} = socket, :save) do
    case EditSession.fetch(session, socket.assigns.block_field, purpose: :save) do
      {:ok, %{state: %Ops{} = state, rev: rev}} -> {state, assign(socket, :save_rev, rev)}
      _ -> {socket.assigns.block_ops, assign(socket, :save_rev, nil)}
    end
  end

  defp session_ops_for(socket, _tag), do: {session_ops(socket), socket}

  # After a save: hand the session the saved rows. It replays the ops that
  # arrived while the save ran and tells the other replicas.
  defp rebase_session(%{assigns: %{edit_session: %Replica{session: session} = replica}} = socket, base) do
    mode = if socket.assigns[:save_rev], do: :own_save, else: :carry

    case EditSession.rebase(session, socket.assigns.block_field, base, mode, replica: true) do
      {:ok, info} ->
        {replica, displayed} = Replica.reset(replica, info)
        {:ok, socket |> assign(:edit_session, replica) |> assign(:save_rev, nil), displayed}

      {:error, _} ->
        :detached
    end
  end

  # A previewed revision that was saved, or a field whose join failed: the
  # saved rows are the newest, so join and carry the others' work onto them.
  defp rebase_session(%{assigns: %{edit_session: status, entry: %{id: id}}} = socket, _base)
       when status in [:detached, :failed] and not is_nil(id) do
    if connected?(socket) and !socket.assigns[:session_detached?] do
      socket = socket |> assign(:edit_session, nil) |> join_session(rebase: true, mounted?: false)

      case socket.assigns.edit_session do
        %Replica{} = replica -> {:ok, socket, Replica.displayed(replica)}
        _ -> :detached
      end
    else
      :detached
    end
  end

  defp rebase_session(_socket, _base), do: :detached

  # Show `new` where the editor showed `socket.assigns.block_ops`: seed forms
  # for roots that appeared, none for roots that went, and a refresh for
  # roots whose subtree changed. `hint` narrows which roots to compare.
  #
  # `mounted?: false` when the blocks have not mounted yet (the connected
  # mount): their seed forms are all they need.
  defp show_state(socket, %Ops{} = new, hint, opts \\ []) do
    old = socket.assigns.block_ops
    also = Keyword.get(opts, :also, [])

    if new == old and also == [] do
      socket
    else
      added = new.order -- old.order
      removed = old.order -- new.order
      changed = Enum.uniq(Ops.changed_roots(old, new, hint) ++ Enum.filter(also, &(&1 in new.order)))

      base =
        Keyword.get_lazy(opts, :base, fn ->
          socket.assigns[:session_base] || Ops.from_entry_blocks(socket.assigns.entry_blocks || [])
        end)

      seeds = Map.new(added, &{&1, materialized_form(socket, new, &1)})

      socket =
        socket
        |> update(:seed_forms, &(&1 |> Map.drop(removed) |> Map.merge(seeds)))
        |> assign_ops(new)
        |> assign(:blocks_changed?, not Ops.pristine?(new, base))

      if Keyword.get(opts, :mounted?, true) do
        socket |> assign(:remote_preview_dirty?, true) |> queue_refresh(changed)
      else
        Enum.reduce(changed, socket, &put_seed_form(&2, &1, materialized_form(&2, new, &1)))
      end
    end
  end

  # The uids an op names, to narrow `Ops.changed_roots/3`. Ops that move or
  # remove blocks compare every root.
  defp hint_uids({:update, uid, _params}), do: [uid]
  defp hint_uids({:set_field, uid, _path, _value, _rev}), do: [uid]
  defp hint_uids({:set_fields, uid, _changes, _rev}), do: [uid]
  defp hint_uids({:insert_child, parent_uid, _uid, _at, _params}), do: [parent_uid]
  defp hint_uids({:reorder_children, parent_uid, _uids}), do: [parent_uid]
  defp hint_uids({:move, _uid, _at}), do: []
  defp hint_uids({:reorder, _uids}), do: []
  defp hint_uids(_op), do: :all

  # Roots changed by other editors are refreshed together, a moment after
  # the first change, and a root this editor works in waits until they leave
  # it: its form is theirs while they type.
  defp queue_refresh(socket, roots) do
    socket = update(socket, :remote_refresh, &MapSet.union(&1, MapSet.new(roots)))

    if socket.assigns.remote_refresh_scheduled? do
      socket
    else
      send_update_after(__MODULE__, [id: socket.assigns.id, event: "flush_remote_refresh"], 120)
      assign(socket, :remote_refresh_scheduled?, true)
    end
  end

  # A root in use is refreshed as well — two editors can work in one block —
  # without re-booting the widget that has the focus (its input is the
  # editor's while they type). It is noted, to be shown once more when the
  # editor leaves the field.
  defp flush_remote_refresh(socket) do
    roots = socket.assigns.remote_refresh
    focus = socket.assigns.local_focus
    {in_use, others} = Enum.split_with(roots, &(&1 == focus))

    socket
    |> assign(:remote_refresh, MapSet.new())
    |> update(:deferred_roots, &MapSet.union(&1, MapSet.new(in_use)))
    |> refresh_roots(others)
    |> refresh_roots(in_use, :skip_focused)
    |> refresh_preview_after_remote()
  end

  # Other editors' changes reach the live preview once per flush, and only
  # while it is open.
  defp refresh_preview_after_remote(%{assigns: %{remote_preview_dirty?: true}} = socket) do
    socket = assign(socket, :remote_preview_dirty?, false)
    if socket.assigns.live_preview_active?, do: refresh_live_preview(socket), else: socket
  end

  defp refresh_preview_after_remote(socket), do: socket

  # `:force` renders the root even when the store holds what was rendered
  # last: the input the editor just left kept their own value while they
  # typed, and only a render puts the session's value into it.
  defp refresh_roots(socket, roots, remount \\ true) do
    now = System.monotonic_time(:millisecond)

    roots
    |> Enum.filter(&(&1 in socket.assigns.block_ops.order))
    |> Enum.reduce(socket, fn root, socket ->
      socket
      |> replace_root_from_store(root, remount)
      |> update(:refreshed_at, &Map.put(&1, root, now))
    end)
  end

  # A keystroke sent while another editor's change to the same root was on
  # its way to the browser carries that root's other inputs as they were.
  # The op is the one field and the store is right, but the block's own form
  # took the old values: show the root from the store again. Only a keystroke
  # that arrives within a round trip of the refresh can have crossed it.
  defp recheck_after_race(socket, op) when elem(op, 0) in [:set_field, :set_fields, :update] do
    uid = elem(op, 1)
    ops = socket.assigns.block_ops
    root = Ops.known?(ops, uid) && Ops.root_of(ops, uid)
    refreshed_at = (socket.assigns[:refreshed_at] || %{})[root]

    if refreshed_at && System.monotonic_time(:millisecond) - refreshed_at < 300,
      do: queue_refresh(socket, [root]),
      else: socket
  end

  defp recheck_after_race(socket, _op), do: socket

  # A root's form built from the store. The params it was cast from are
  # dropped: a form reads a field from `params` before `data`, so a mounted
  # block would otherwise take its untouched children as raw param maps
  # (`block[:children].value`) instead of the rows.
  defp materialized_form(socket, %Ops{} = ops, root_uid) do
    {:ok, params} = Ops.materialize_root(ops, root_uid)

    socket
    |> materialize_base_struct(root_uid)
    |> socket.assigns.block_module.changeset(params, socket.assigns.current_user.id, true)
    |> without_params()
    |> to_form(as: "entry_block", id: "entry_block_form-#{root_uid}")
  end

  defp without_params(%Changeset{} = changeset),
    do: %{changeset | params: nil, changes: Map.new(changeset.changes, fn {k, v} -> {k, without_params(v)} end)}

  defp without_params(list) when is_list(list), do: Enum.map(list, &without_params/1)
  defp without_params(other), do: other

  defp subtree_dirty?(%Ops{} = ops, uid) do
    Ops.known?(ops, uid) and
      Enum.any?([uid | Ops.descendants(ops, uid)], &(Map.get(ops.diffs, &1, %{}) != %{} or ops.statuses[&1] == :inserted))
  end

  defp seeds_for_new_roots(socket, %Ops{} = ops, known) do
    ops.order
    |> Enum.reject(&(&1 in known))
    |> Map.new(&{&1, materialized_form(socket, ops, &1)})
  end

  # Read this field's rows again, for a rebase onto rows someone else wrote.
  # The Form's copy of the entry follows, so its save starts from them too.
  defp reload_entry_blocks(socket) do
    %{entry: %{__struct__: schema, id: entry_id}, block_field: field} = socket.assigns
    {_assoc, query} = schema |> Brando.Content.BlockPreloads.for_schema() |> List.keyfind(:"entry_#{field}", 0)
    entry_blocks = Brando.Repo.all(from(j in query, where: j.entry_id == ^entry_id))

    send_update(BrandoAdmin.Components.Form,
      id: socket.assigns.form_id,
      event: "entry_blocks_reloaded",
      block_field: field,
      entry_blocks: entry_blocks
    )

    assign(socket, :entry_blocks, entry_blocks)
  end

  defp restore_draft(socket, changesets, originals) do
    # Seed from the saved entry, then replay a complete replacement through the
    # reducer. This retains owned IDs and deletion tombstones for the next save.
    # The result reaches the session (and the other editors) as one
    # `{:replace_state, ops}` op.
    ops = Ops.from_entry_blocks(originals)

    forms =
      Enum.map(changesets, fn cs ->
        uid = cs |> Changeset.get_assoc(:block) |> Changeset.get_field(:uid)
        {uid, to_form(cs, as: "entry_block", id: "entry_block_form-#{uid}")}
      end)

    wanted = Enum.map(forms, &elem(&1, 0))

    ops =
      Enum.reduce(ops.order -- wanted, ops, fn uid, acc ->
        {:ok, next} = Ops.apply_op(acc, {:delete, uid})
        next
      end)

    saved = Map.new(originals, &{&1.block.uid, &1})

    ops =
      Enum.reduce(forms, ops, fn {uid, form}, acc ->
        params = Brando.Drafts.Params.snapshot(form.source)

        cond do
          # A block the copy holds as it is saved is no change: in a shared
          # session it must not overwrite what others did to it.
          unchanged?(saved[uid], params, socket) -> acc
          Ops.known?(acc, uid) -> next!(acc, {:update, uid, params})
          true -> next!(acc, {:insert, uid, :end, params})
        end
      end)

    {:ok, ops} = Ops.apply_op(ops, {:reorder, wanted})

    case socket.assigns[:edit_session] do
      %Replica{} ->
        # Others share this field: the copy's changes are carried onto what
        # the session holds (`{:carry, ...}`), so their unsaved work stays —
        # and with it the recovery copies their next capture writes.
        restore_into_session(socket, ops, Ops.from_entry_blocks(originals))

      _ ->
        for {uid, form} <- forms, uid in socket.assigns.root_order do
          send_update(Block, id: "block-#{uid}", event: "replace_form", form: form)
        end

        socket
        |> assign(:entry_blocks, originals)
        |> assign(:seed_forms, Map.new(forms))
        |> apply_block_op({:replace_state, ops}, :replay)
        |> assign(:block_bin, [])
    end
  end

  # Each of the revision's blocks as a change to the row it has now. A
  # block the entry no longer has comes back as a new one: its old rows (a
  # revision keeps them) still hold its uid and its refs' uids.
  defp working_copy_changesets(socket, revision_blocks, rows) do
    %{block_module: block_module, current_user: %{id: user_id}} = socket.assigns
    by_uid = Map.new(rows, &{&1.block.uid, &1})

    Enum.map(revision_blocks, fn entry_block ->
      params =
        block_module
        |> to_change_form(entry_block, %{}, user_id)
        |> Map.fetch!(:source)
        |> Brando.Drafts.Params.snapshot()

      case by_uid[entry_block.block.uid] do
        nil ->
          params = params |> strip_row_ids() |> Map.update!("block", &as_new_block/1)
          block_module |> struct(%{}) |> Map.put(:block, empty_block()) |> block_module.changeset(params, user_id, true)

        row ->
          block_module.changeset(row, params, user_id, true)
      end
    end)
  end

  defp empty_block, do: %Brando.Content.Block{vars: [], refs: [], table_rows: [], children: [], block_identifiers: []}

  defp as_new_block(%{} = block) do
    block
    |> Map.put("uid", Brando.Utils.generate_uid())
    |> Map.update("refs", [], fn refs -> Enum.map(refs, &Map.put(&1, "uid", Brando.Utils.generate_uid())) end)
    |> Map.update("children", [], fn children -> Enum.map(children, &as_new_block/1) end)
  end

  # Leave the edit session to show something the others do not see. The
  # replica is let go first, so the field never rejoins with what it showed.
  defp detach_session(%{assigns: %{edit_session: %Replica{session: session, monitor: monitor}}} = socket) do
    Process.demonitor(monitor, [:flush])
    Process.delete({:brando_edit_session_monitor, monitor})
    EditSession.detach(session, socket.assigns.block_field)
    assign(socket, :edit_session, :detached)
  end

  defp detach_session(socket), do: assign(socket, :edit_session, :detached)

  defp next!(ops, op) do
    {:ok, next} = Ops.apply_op(ops, op)
    next
  end

  defp unchanged?(nil, _params, _socket), do: false

  defp unchanged?(row, params, socket) do
    saved = to_change_form(socket.assigns.block_module, row, %{}, socket.assigns.current_user.id)
    Brando.Drafts.Params.snapshot(saved.source) == params
  end

  defp restore_into_session(socket, ops, base) do
    op = {:carry, ops, base}
    {:ok, restored} = Ops.apply_op(socket.assigns.block_ops, op)

    socket
    |> show_state(restored, :all)
    |> refresh_roots(restored.order -- (restored.order -- socket.assigns.root_order))
    |> submit_to_session(op)
    |> assign(:block_bin, [])
    |> assign(:blocks_changed?, true)
    |> tap(fn socket -> send_update(BrandoAdmin.Components.Form, id: socket.assigns.form_id, event: "draft_dirty") end)
  end

  defp joined_with_work?(%{assigns: %{edit_session: %Replica{}}} = socket),
    do: not Ops.pristine?(socket.assigns.block_ops, Ops.from_entry_blocks(socket.assigns.entry_blocks || []))

  defp joined_with_work?(_socket), do: false

  # Build with AI opens the content assistant for this entry and field. It is
  # offered when the assistant has a model, the user may use it, and the
  # content type is one the assistant can change.
  defp assistant?(%{opts: opts}) when is_map_key(opts, :footnote_fields), do: false
  defp assistant?(%{entry: nil}), do: false

  defp assistant?(%{entry: entry, current_user: user}) do
    entry.__struct__ in Brando.Content.Transfer.Catalog.schemas() and Brando.AI.Agent.allowed?(user) and
      Brando.AI.Agent.available?()
  end

  # The empty field says where templates are added to the people who can add
  # them: whoever may create templates, or a superuser — the one who sees
  # Configuration → Templates — without the authorization engine.
  defp manages_templates?(%{templates: [_ | _]}), do: false

  defp manages_templates?(%{current_user: user}) do
    if Brando.Authorization.enabled?(),
      do: Brando.Authorization.can?(Brando.Authorization.Scope.current(user), :create, Brando.Content.Template),
      else: match?(%{role: :superuser}, user)
  end

  defp assistant_url(entry, block_field) do
    query =
      URI.encode_query(%{
        "content_type" => Brando.Content.Proposals.Codec.content_type(entry.__struct__),
        "id" => entry.id,
        "field" => block_field
      })

    "/admin/assistant?" <> query
  end

  # The changeset base for materializing a root block: its persisted entry
  # block when it exists, otherwise a fresh struct with an empty (loaded)
  # block so cast_assoc has something to cast against.
  # Rebuild a child's changeset from the op store — the only holder of its
  # current content once its own component has been destroyed by a move.
  defp build_child_changeset(socket, uid) do
    with {:ok, params} <- Ops.materialize_child(socket.assigns.block_ops, uid) do
      {:ok,
       socket
       |> child_base_struct(uid)
       |> Brando.Content.Block.recursive_block_changeset(params, socket.assigns.current_user.id)}
    end
  end

  # The persisted row a moved child should cast over, so `cast_assoc` matches
  # existing ids instead of inserting duplicates. Children live anywhere in the
  # tree, hence the walk; an unsaved child has no row and gets a fresh base.
  defp child_base_struct(socket, uid) do
    socket.assigns.entry_blocks
    |> List.wrap()
    |> Enum.map(& &1.block)
    |> find_block_by_uid(uid)
    |> case do
      nil -> %Brando.Content.Block{vars: [], refs: [], table_rows: [], children: [], block_identifiers: []}
      block -> block
    end
  end

  defp find_block_by_uid(blocks, uid) do
    Enum.find_value(blocks, fn
      %{uid: ^uid} = block -> block
      %{children: children} when is_list(children) -> find_block_by_uid(children, uid)
      _ -> nil
    end)
  end

  defp materialize_base_struct(socket, uid) do
    case Enum.find(socket.assigns.entry_blocks || [], &(&1.block.uid == uid)) do
      nil ->
        base_block = %Brando.Content.Block{vars: [], refs: [], table_rows: [], children: [], block_identifiers: []}
        socket.assigns.block_module |> struct(%{}) |> Map.put(:block, base_block)

      entry_block ->
        entry_block
    end
  end

  defp collection_owner(socket, uid) do
    if Ops.known?(socket.assigns.block_ops, uid) do
      root_uid = Ops.root_of(socket.assigns.block_ops, uid)
      {:ok, params} = Ops.materialize_root(socket.assigns.block_ops, root_uid)

      root =
        socket
        |> materialize_base_struct(root_uid)
        |> socket.assigns.block_module.changeset(params, socket.assigns.current_user.id, true)
        |> Changeset.get_assoc(:block, :struct)

      case find_block_by_uid([root], uid) do
        %{type: :module, multi: false} = owner -> {:ok, owner}
        _ -> {:error, :invalid_owner}
      end
    else
      {:error, :unknown_owner}
    end
  end

  # The mounted root takes its new form through `replace_form`. Its seed
  # is only read when it mounts again, and writing `@seed_forms` would
  # re-render every root's shell (AGENTS.md: derived assigns) — so it is left
  # alone, except in frontend edit mode, where a root mounts again whenever
  # the selection moves to it.
  defp replace_root_from_store(socket, root_uid, remount \\ true) do
    form = materialized_form(socket, socket.assigns.block_ops, root_uid)

    {form, remount} =
      if remount == :force,
        do: {%{form | options: Keyword.put(form.options, :rendered_at, System.unique_integer())}, true},
        else: {form, remount}

    send_update(Block, id: "block-#{root_uid}", event: "replace_form", form: form, remount_js: remount)
    if socket.assigns.focus, do: put_seed_form(socket, root_uid, form), else: socket
  end

  # The op chokepoint for this editor's own mutations (structural or
  # content). A rejected op means a caller drifted from the store — log it
  # loudly, keep the socket usable. An applied op is cast to the edit session.
  # Other editors' ops do not come through here: see
  # `handle_session_message/2`.
  # A synchronized translation's structure follows its source. Structural ops
  # from this editor are refused; `:replay` ops — reconnect recovery, an
  # applied recovery copy — replay what was already accepted.
  defp apply_block_op(socket, op, mode \\ :local)

  defp apply_block_op(%{assigns: %{source_locked: true}} = socket, op, :local)
       when elem(op, 0) in @structural_ops,
       do: refuse_structure(socket, elem(op, 0))

  defp apply_block_op(socket, op, mode) do
    op = keyed(socket, op)

    case Ops.apply_op(socket.assigns.block_ops, op) do
      {:ok, ops_state} ->
        send_update(BrandoAdmin.Components.Form, id: socket.assigns.form_id, event: "draft_dirty")
        # The frontend editor's own edits, not ones synced from other editors.
        if mode == :local and socket.assigns.focus, do: send(self(), {:frontend_edit, :dirty})

        socket
        |> assign_ops(ops_state)
        |> assign(:blocks_changed?, true)
        |> submit_to_session(op)
        |> recheck_after_race(op)

      {:error, reason} ->
        Logger.error(
          "BlockField (#{socket.assigns.block_field}) rejected block op " <>
            "#{inspect(elem(op, 0))}: #{inspect(reason)}"
        )

        socket
    end
  end

  defp refuse_structure(socket, what) do
    Logger.warning("BlockField (#{socket.assigns.block_field}) refused #{inspect(what)} in a synchronized translation")

    send(
      self(),
      {:toast, gettext("Blocks in this translation follow the source. Add, remove or move them in the source.")}
    )

    socket
  end

  # `root_order` is the render projection of the store — assigned together
  # with `block_ops` so they can never drift. `assign/3` no-ops on equal
  # values, so content-only ops (order list untouched, reference-equal) never
  # dirty `root_order` and typing never re-evaluates the shell comprehension.
  defp assign_ops(socket, ops_state) do
    socket
    |> assign(:block_ops, ops_state)
    |> assign(:root_order, ops_state.order)
    |> maybe_assign_starting_modules()
    |> notify_note_observers()
  end

  # The modules an empty field offers to start with (see
  # `Brando.Content.StartingModules`). Looked up once, when the field is first
  # seen empty — at mount, or when its last block is deleted — and never for a
  # field that has blocks. The counts behind them are cached per site, field
  # and language, so the connected mount after the dead render reads no rows.
  defp maybe_assign_starting_modules(
         %{assigns: %{root_order: [], note_collection?: false, focus: nil, module_set: module_set} = assigns} = socket
       )
       when not is_map_key(assigns, :starting_modules) do
    %{block_module: block_module, entry: entry, opts: opts} = assigns

    modules =
      Brando.Content.StartingModules.list(block_module, ModulePicker.root_modules(module_set),
        language: Map.get(entry, :language),
        starts_with: opts[:starts_with]
      )

    schema = entry.__struct__

    socket
    |> assign(:starting_modules, modules)
    |> assign(:welcome_title, start_title(schema))
    |> assign(:welcome_lead, start_lead(schema, modules))
  end

  defp maybe_assign_starting_modules(socket), do: socket

  # "Start this case". A blueprint can word it for a language where the
  # phrase agrees with the noun ("Start et nytt prosjekt") by translating the
  # msgid `"Start this %{type}"` in its own Gettext domain; otherwise Brando's
  # string is used.
  defp start_title(schema) do
    type = String.downcase(Brando.Blueprint.get_singular(schema))
    blueprint_start_title(schema, type) || gettext("Start this %{type}", type: type)
  end

  defp blueprint_start_title(schema, type) do
    %{domain: domain, schema: schema_name} = schema.__naming__()
    gettext_domain = String.downcase("#{domain}_#{schema_name}")
    title = Gettext.dgettext(schema.__modules__().gettext, gettext_domain, "Start this %{type}", type: type)

    # Untranslated, Gettext returns the msgid itself
    if title != "Start this #{type}", do: title
  rescue
    _ -> nil
  end

  defp start_lead(schema, modules) do
    if Enum.any?(modules, &(&1.source == :first)),
      do: gettext("%{types} usually start with one of these.", types: Brando.Blueprint.get_plural(schema)),
      else: gettext("Pick a first block.")
  end

  # A tile is named for its action ("Start with Heading"); the container it
  # comes in and its count describe it.
  defp starting_module_description(id, index, tile) do
    [tile.container && "#{id}-starting-#{index}-container", tile.count && "#{id}-starting-#{index}-count"]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> then(&if(&1 == "", do: nil, else: &1))
  end

  defp field_note_slots(socket) do
    Enum.map(socket.assigns.block_ops.order, fn uid ->
      {:ok, params} = Ops.materialize_root(socket.assigns.block_ops, uid)

      socket
      |> materialize_base_struct(uid)
      |> socket.assigns.block_module.changeset(params, socket.assigns.current_user.id, true)
      |> Changeset.get_assoc(:block, :struct)
    end)
  end

  defp notify_note_observers(socket) do
    observers = socket.assigns[:note_observers] || %{}

    if map_size(observers) > 0 do
      slots = field_note_slots(socket)

      Enum.each(observers, fn {field, observer} ->
        items =
          slots
          |> CollectionLifecycle.unused_notes(field, observer.html)
          |> Enum.map(
            &%{uid: &1.uid, kind: :footnote, name: &1.slot_name, label: CollectionLifecycle.label(&1), restore?: true}
          )

        send_update(observer.reply_to, event: "notes", items: items)
      end)
    end

    socket
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
  #
  # `:changed` (after a save) skips the roots that provably hold the saved
  # rows already. Re-seeding one re-sends its whole form (~8 KB, one frame
  # per root) even when nothing in it changed — 1.1 MB for a save at 115
  # roots. See `holds_persisted?/2` for what "provably" means.
  defp reload_all_blocks(socket, scope \\ :all) do
    user_id = socket.assigns.current_user.id
    block_module = socket.assigns.block_module
    entry_blocks = socket.assigns.entry_blocks || []

    entry_blocks_forms = Enum.map(entry_blocks, &to_change_form(block_module, &1, %{}, user_id))
    base = Ops.from_entry_blocks(entry_blocks)

    case reload_state(assign(socket, :session_base, base), base, scope) do
      {:ok, socket, state} -> reseed_from_state(socket, entry_blocks_forms, state, base, scope)
      :detached -> reseed_from_rows(socket, entry_blocks_forms, base, scope)
    end
  end

  # After a save (`:changed`) the session moves onto the saved rows. Other
  # reloads show what the session already holds.
  defp reload_state(socket, base, :changed), do: rebase_session(socket, base)

  defp reload_state(%{assigns: %{edit_session: %Replica{}}} = socket, _base, _scope),
    do: {:ok, socket, socket.assigns.block_ops}

  defp reload_state(_socket, _base, _scope), do: :detached

  # Ops of other editors that are not saved yet sit on top of the rows: the
  # roots they touch show the session's state, not the rows.
  defp reseed_from_state(socket, entry_blocks_forms, state, base, scope) do
    forms =
      Map.new(entry_blocks_forms, fn form ->
        uid = get_form_block_uid(form)
        if subtree_dirty?(state, uid), do: {uid, materialized_form(socket, state, uid)}, else: {uid, form}
      end)

    for {uid, form} <- forms, scope == :all or subtree_dirty?(state, uid) or not holds_persisted?(socket, form) do
      send_update(Block, id: "block-#{uid}", event: "replace_form", form: form)
    end

    socket
    |> assign(:seed_forms, Map.merge(forms, seeds_for_new_roots(socket, state, Map.keys(forms))))
    |> assign_ops(state)
    |> assign(:block_bin, [])
    |> assign(:blocks_changed?, not Ops.pristine?(state, base))
  end

  defp reseed_from_rows(socket, entry_blocks_forms, base, scope) do
    for form <- entry_blocks_forms, scope == :all or not holds_persisted?(socket, form) do
      send_update(Block, id: "block-#{get_form_block_uid(form)}", event: "replace_form", form: form)
    end

    socket
    |> assign(:seed_forms, Map.new(entry_blocks_forms, &{get_form_block_uid(&1), &1}))
    |> assign_ops(base)
    # bin snapshots don't survive a save — the save deleted the underlying
    # rows, so their captured db ids are stale.
    |> assign(:block_bin, [])
    |> assign(:blocks_changed?, false)
  end

  # Whether the mounted root behind `form` (freshly loaded after a save)
  # already holds exactly that row, so re-seeding it would change nothing.
  # All three are required; a root failing any of them is re-seeded, as every
  # root used to be:
  #
  #   * The store has no diff for the root or anything under it, so the
  #     mounted form is still its seed form. An edited root keeps a form
  #     rebased on pre-save data even when its values were saved verbatim.
  #   * The row it was seeded from snapshots equal to the reloaded row — ids,
  #     sequence, children, vars and refs included. A form whose data is a
  #     stale row (a reorder shifted its sequence, a child got an id) is not
  #     the saved entry, even where that difference is ignored at save time.
  #   * What the editor would save for it — the store's materialization cast
  #     onto the seeded row, exactly what the save cast — equals it too. That
  #     catches structure the editor shows but the save did not persist.
  defp holds_persisted?(socket, form) do
    alias Brando.Drafts.Params

    uid = get_form_block_uid(form)
    ops = socket.assigns.block_ops

    with %{source: %Changeset{data: seeded_row} = seed} <- Map.get(socket.assigns.seed_forms, uid),
         :persisted <- Map.get(ops.statuses, uid),
         false <- Enum.any?([uid | Ops.descendants(ops, uid)], &Map.has_key?(ops.diffs, &1)),
         saved = Params.snapshot(form.source),
         true <- Params.snapshot(seed) == saved,
         {:ok, params} <- Ops.materialize_root(ops, uid) do
      held = socket.assigns.block_module.changeset(seeded_row, params, socket.assigns.current_user.id, true)
      Params.snapshot(held) == saved
    else
      _ -> false
    end
  end

  # Capture the doomed subtree for undo BEFORE the delete tears it down.
  # Local deletes only — the deleting editor gets the undo toast; the restore
  # is an op, so every editor's store resurrects the block (leaving a uid in
  # a remote `deleted` list would kill the rows again on their next save).
  defp stash_in_bin(socket, uid) do
    ops = socket.assigns.block_ops

    if Ops.known?(ops, uid) do
      update(socket, :block_bin, &[Ops.bin_snapshot(ops, uid) | &1])
    else
      socket
    end
  end

  # Undo a delete: replay the bin snapshot into the op store (a `{:restore,
  # snapshot}` op), then bring the block back on screen. A restored ROOT
  # mounts a fresh component from its re-materialized seed form (the shell
  # comprehension picks it up from ops.order); a restored CHILD lives inside a
  # mounted parent that owns its form, so the root gets the `replace_form`
  # cascade + remount push — the same path remote ops use (the only
  # sanctioned post-mount form handoff).
  defp restore_from_snapshot(socket, %{uids: [uid | _], location: location} = snapshot) do
    with {:ok, updated_ops} <- Ops.apply_op(socket.assigns.block_ops, {:restore, snapshot}) do
      root_uid = Ops.root_of(updated_ops, uid)
      new_form = materialized_form(socket, updated_ops, root_uid)

      socket =
        socket
        |> put_seed_form(root_uid, new_form)
        |> apply_block_op({:restore, snapshot}, :replay)

      case location do
        {:root, _at} ->
          :ok

        {:child, _parent_uid, _at} ->
          send_update(Block, id: "block-#{root_uid}", event: "replace_form", form: new_form, remount_js: true)
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
  defp focus_shells(root_order, seed_forms, %{root: root}) do
    root_order
    |> root_shells(seed_forms)
    |> Enum.filter(fn {uid, _, _} -> uid == root end)
  end

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
      apply_block_op(acc, {:insert, uid, :end, Ops.block_diff_params(form.source)}, :replay)
    end)
    |> apply_block_op({:reorder, merged_uids}, :replay)
  end

  # reposition a main block
  @locked_client_events ~w(reposition paste_block_at_end restore_block outline_root_reposition outline_reposition start_from_template
                           insert_starting_module)

  def handle_event(event, _params, %{assigns: %{source_locked: true}} = socket) when event in @locked_client_events,
    do: {:noreply, refuse_structure(socket, event)}

  def handle_event("reposition", %{"new" => new_idx, "old" => old_idx}, socket) when new_idx == old_idx do
    # same index, no move needed
    {:noreply, socket}
  end

  def handle_event("reposition", %{"uid" => uid, "new" => new_idx, "old" => _old_idx}, socket) do
    socket
    |> apply_block_op({:move, uid, new_idx})
    |> refresh_live_preview()
    |> then(&{:noreply, &1})
  end

  # "Start from a template", offered while the field is empty: each of the
  # template's root blocks goes in as a copy, as pasting it would. Only a
  # template this field offers, and only into an empty field, so a stale
  # click can't pour a second set of blocks into a page being written.
  def handle_event("start_from_template", %{"id" => id}, socket) do
    with true <- socket.assigns.block_ops.order == [],
         {template_id, ""} <- Integer.parse(to_string(id)),
         true <- Enum.any?(socket.assigns.templates, &(&1.id == template_id)) do
      socket =
        template_id
        |> Brando.Content.StartingTemplates.blocks()
        |> Enum.with_index()
        |> Enum.reduce(socket, fn {block, sequence}, acc ->
          insert_pasted_root_block(acc, %{changeset: Changeset.change(block)}, sequence)
        end)

      {:noreply, socket}
    else
      _ -> {:noreply, socket}
    end
  end

  # A starting module (`@starting_modules`), offered while the field is empty:
  # the module goes in first, the same way the module picker inserts it, or
  # with the container it usually starts in. Only a tile this field offers,
  # and only into an empty field, as with templates.
  def handle_event("insert_starting_module", %{"module" => module_ref} = params, socket) do
    container_ref = params["container"] |> to_string() |> String.trim() |> then(&if(&1 == "", do: nil, else: &1))

    offered? =
      Enum.any?(
        socket.assigns[:starting_modules] || [],
        &(&1.module_ref == module_ref and &1.container_ref == container_ref)
      )

    cond do
      socket.assigns.block_ops.order != [] or not offered? -> {:noreply, socket}
      container_ref -> {:noreply, insert_root_container_with_module(socket, container_ref, module_ref)}
      true -> {:noreply, insert_root_module(socket, module_ref, 0)}
    end
  end

  def handle_event("paste_block_at_end", _, socket) do
    {:noreply, paste_root_block(socket, length(socket.assigns.block_ops.order))}
  end

  # A paste never consumes the clipboard — copying once and pasting into
  # several spots, or several entries, is the point of it living in the cache
  # — so this is the way out. Cheap by construction: `data-paste-allow` is one
  # attribute on this component's own root, so dropping the clipboard hides
  # every root/container paste button without touching a single block.
  def handle_event("clear_clipboard", _, socket) do
    Brando.Cache.del(clipboard_key(socket.assigns.current_user.id))
    {:noreply, assign_clipboard_meta(socket, nil)}
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
    socket
    |> apply_block_op({:move, uid, new_idx})
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
      # Cross-parent: extract from source, insert into target.
      #
      # Pre-flight the rebuild BEFORE telling the source to release the child.
      # `extract_child` drops it from the source's `block_list`/`changesets`
      # unconditionally, so discovering a problem afterwards leaves the block
      # off-canvas with no rollback path. Failing here instead is a clean no-op:
      # nothing has moved yet.
      case build_child_changeset(socket, uid) do
        {:ok, _cs} ->
          send_update(Block,
            id: "block-#{from_parent_uid}",
            event: "extract_child",
            child_uid: uid,
            target_parent_uid: to_parent_uid,
            target_sequence: new_idx
          )

        {:error, reason} ->
          require Logger

          Logger.error("""
          [BlockField] refusing cross-parent move of #{inspect(uid)}: #{inspect(reason)}. \
          The block stays under its original parent.
          """)
      end
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
  (`block_module.changeset/4` with `recursive?: true`), so all form field values
  — vars, refs, table_rows — and the block's whole child subtree are properly
  cast and restored, not just the root block's own fields.
  """
  def handle_event("recover_blocks", params, socket) do
    %{"rootUids" => root_uids, "missingUids" => missing_uids, "forms" => forms} = params
    child_order = Map.get(params, "childOrder", %{})
    missing_uids = recoverable_uids(missing_uids, socket)

    if missing_uids == [] do
      {:reply, %{recovered: []}, socket}
    else
      block_module = socket.assigns.block_module
      user_id = socket.assigns.current_user.id
      entry_id = socket.assigns.entry.id

      # Build forms for missing blocks by casting recovered params through
      # the normal changeset pipeline — this preserves all form field values
      recovered_forms =
        for uid <- missing_uids, reduce: %{} do
          acc -> put_recovered_form(acc, uid, forms, child_order, block_module, user_id, entry_id)
        end

      if recovered_forms == %{} do
        {:reply, %{recovered: []}, socket}
      else
        # Merge recovered seeds in, then let ONE reorder to the client's
        # pre-disconnect root order set structure — sequence derives from
        # list order at materialization, so no per-form sequence restamp.
        seed_forms = Map.merge(socket.assigns.seed_forms, recovered_forms)
        merged_uids = Enum.filter(root_uids, &Map.has_key?(seed_forms, &1))

        # The reply is what lets the client drop its sessionStorage snapshot.
        # Until it lands, the client keeps the only copy of these never-persisted
        # blocks — see `maybeRecoverBlocks` in the BlockField hook.
        socket
        |> assign(:seed_forms, seed_forms)
        |> apply_recovered_block_ops(recovered_forms, merged_uids)
        |> refresh_live_preview()
        |> then(&{:reply, %{recovered: Map.keys(recovered_forms)}, &1})
      end
    end
  end

  defp put_recovered_form(acc, uid, forms, child_order, block_module, user_id, entry_id) do
    form_id = "entry_block_form-#{uid}"
    form_data = forms[form_id]

    if form_data do
      entry_block_params =
        form_data
        |> Map.get("entry_block", %{})
        |> sanitize_recovered_params(uid, block_module, user_id)

      # Create base struct with an empty block so cast_assoc has
      # a loaded association to work with (not NotLoaded). Nested
      # children are built by Ecto from the params below, exactly as
      # on the save path (`materialize_base_struct/2`).
      base_block = %Brando.Content.Block{
        vars: [],
        refs: [],
        table_rows: [],
        children: [],
        block_identifiers: []
      }

      base_struct = block_module |> struct(%{}) |> Map.put(:block, base_block)

      # Include entry_id in params (no hidden field for it in the form)
      params_with_entry =
        entry_block_params
        |> Map.put("entry_id", to_string(entry_id))
        |> put_recovered_children(uid, forms, child_order, %{
          block_module: block_module,
          user_id: user_id
        })

      # `recursive?: true` is load-bearing — the non-recursive block
      # cast has no `cast_assoc(:children)` and drops the subtree
      # assembled just above without a word.
      entry_block_cs =
        base_struct
        |> block_module.changeset(params_with_entry, user_id, true)
        |> Map.put(:action, :insert)

      # Keyed by the uid the server vetted, never by one read back out of
      # the client's params — otherwise a payload whose `missingUids`
      # and whose form body disagree could land under a uid that was
      # never checked, clobbering a live block's seed form.
      entry_block_form =
        to_form(entry_block_cs,
          as: "entry_block",
          id: "entry_block_form-#{uid}"
        )

      Map.put(acc, uid, entry_block_form)
    else
      acc
    end
  end

  # ── Recovery is a client-authored write path ────────────────────────────────
  #
  # `recover_blocks` is the one place where a raw params tree from the browser is
  # cast straight into new DB rows. Everything else the editor sends is a
  # `validate` against a changeset the server already built. So the params are
  # narrowed here before they reach `changeset/4`:
  #
  #   * the entry_block level is whitelisted, which drops `block_id` — casting it
  #     would attach this entry to an existing block row belonging to another
  #     entry (`blueprint.ex:318` casts it, `entry_id` alone does not protect it)
  #   * the block level is whitelisted from `@block_attrs` minus the fields that
  #     are server authority: `creator_id`, `parent_id`, `source`
  #   * `creator_id` and `source` are then *forced*, and `uid` is forced to the
  #     uid the server vetted
  #   * the same scrub runs over every nested relation — a var or ref carries
  #     `creator_id`, `block_id` and `page_id` of its own
  #
  # Fields left castable (`module_id`, `container_id`, `palette_id`,
  # `fragment_id`) are not a boundary: every admin can already pick any of them
  # from the pickers. The boundary is ownership and identity.

  @recoverable_entry_block_params ~w(sequence)
  # `children` is deliberately absent: the subtree only ever arrives through the
  # vetted `childOrder` graft below, where each child is sanitized in its own
  # right. Accepting it here would be a way to smuggle in blocks that never got
  # a uid or a creator forced onto them.
  @recoverable_block_params ~w(
    uid type active collapsed anchor description multi sequence
    module_id container_id fragment_id palette_id identifier_metas
    vars refs table_rows block_identifiers
  )
  # Stripped wherever they appear in the tree, at any depth.
  @forged_params ~w(id block_id parent_id creator_id source entry_id page_id)

  defp sanitize_recovered_params(entry_block_params, uid, block_module, user_id) do
    block_params =
      entry_block_params
      |> Map.get("block", %{})
      |> sanitize_recovered_block(uid, block_module, user_id)

    entry_block_params
    |> Map.take(@recoverable_entry_block_params)
    |> Map.put("block", block_params)
  end

  defp sanitize_recovered_block(block_params, uid, block_module, user_id) when is_map(block_params) do
    block_params
    |> Map.take(@recoverable_block_params)
    |> Map.new(fn {key, value} -> {key, scrub_forged(value)} end)
    |> Map.put("uid", uid)
    |> Map.put("creator_id", to_string(user_id))
    |> Map.put("source", to_string(block_module))
  end

  defp sanitize_recovered_block(_block_params, uid, block_module, user_id),
    do: sanitize_recovered_block(%{}, uid, block_module, user_id)

  # Recursive scrub for the nested relations, whose field sets are large and
  # mostly legitimate — only the ownership/identity keys are removed.
  defp scrub_forged(%{} = params) do
    params
    |> Map.drop(@forged_params)
    |> Map.new(fn {key, value} -> {key, scrub_forged(value)} end)
  end

  defp scrub_forged(params) when is_list(params), do: Enum.map(params, &scrub_forged/1)
  defp scrub_forged(params), do: params

  # A uid is recoverable only if this process does not already have it. The
  # client decides what *looks* missing by diffing the DOM; the server is the
  # only side that knows what it actually holds, and it must not let a replayed
  # or forged payload overwrite a block that is alive right now.
  defp recoverable_uids(missing_uids, socket) when is_list(missing_uids) do
    known = MapSet.new(socket.assigns.block_ops.order)
    seeded = socket.assigns.seed_forms

    Enum.filter(missing_uids, fn uid ->
      is_binary(uid) and not MapSet.member?(known, uid) and not Map.has_key?(seeded, uid)
    end)
  end

  defp recoverable_uids(_missing_uids, _socket), do: []

  # Graft the captured child subtree onto a recovered root's block params.
  #
  # The client captures every block form on disconnect, but children live in
  # their own `child_block_form-<uid>` forms with no structural link to the
  # parent in the params themselves — the nesting is only in the DOM. So the
  # hook also sends `childOrder`, a parent-uid → ordered-child-uids map read off
  # the `data-parent_uid` wrappers, and the tree is rebuilt here.
  #
  # Order is preserved because sequence is derived from list position at
  # materialization; a set would silently reshuffle the block's children.
  defp put_recovered_children(entry_block_params, uid, forms, child_order, ctx) do
    case recovered_children(uid, forms, child_order, ctx) do
      [] ->
        entry_block_params

      children ->
        block_params = Map.get(entry_block_params, "block", %{})
        Map.put(entry_block_params, "block", Map.put(block_params, "children", children))
    end
  end

  defp recovered_children(uid, forms, child_order, ctx) do
    child_order
    |> Map.get(uid, [])
    |> Enum.map(&recovered_child_params(&1, forms, child_order, ctx))
    |> Enum.reject(&is_nil/1)
  end

  defp recovered_child_params(child_uid, forms, child_order, ctx) do
    %{block_module: block_module, user_id: user_id} = ctx

    case forms["child_block_form-#{child_uid}"] do
      %{"child_block" => child_params} when is_map(child_params) ->
        # Children go through the same narrowing as the root — a nested block is
        # no less client-authored than the one wrapping it.
        sanitized = sanitize_recovered_block(child_params, child_uid, block_module, user_id)

        case recovered_children(child_uid, forms, child_order, ctx) do
          [] -> sanitized
          grandchildren -> Map.put(sanitized, "children", grandchildren)
        end

      _ ->
        nil
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

  # Frontend edit mode: the root holding the selected block, and nothing
  # around it. Structure (adding, moving and removing roots) belongs to the
  # full editor. See `BrandoAdmin.Components.Form.FrontendEditor`.
  def render(%{focus: %{}} = assigns) do
    ~H"""
    <div
      id={"#{@id}-wrapper"}
      phx-hook="Brando.BlockField"
      class={["blocks-wrapper is-frontend-focus", @source_locked && "is-source-locked"]}
      data-block-field={"#{@form_name}[#{@block_field}]"}
      data-entry-id={@entry.id}
      data-paste-allow={Block.Render.paste_allow(@clipboard_meta)}
    >
      <p :if={@source_locked && @focus.root} class="blocks-source-note">
        {gettext("Blocks, their order and media follow the source. Edit the text here.")}
      </p>
      <div class="blocks-content">
        <.live_component
          :if={@focus.root}
          module={BrandoAdmin.Components.Form.BlockField.ModulePicker}
          id={"block-field-#{@block_field}-module-picker"}
          templates={[]}
          hide_fragments={false}
          hide_sections={false}
        />
        <div id={"block-field-#{@block_field}"}>
          <.inputs_for
            :let={block}
            :for={{uid, entry_block_form, list_index} <- focus_shells(@root_order, @seed_forms, @focus)}
            :key={uid}
            field={entry_block_form[:block]}
            skip_hidden
          >
            <div
              id={"base-#{block[:uid].value}"}
              data-id={entry_block_form[:id].value}
              data-uid={block[:uid].value}
              class="entry-block"
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
                slot_open={@open_slot_uid == block[:uid].value}
                slot_title={@slot_title}
                paste_multi_module_id={@paste_multi_module_id}
                live_preview_active?={@live_preview_active?}
                live_preview_cache_key={@live_preview_cache_key}
                focus={@focus}
                level={0}
              />
            </div>
          </.inputs_for>
        </div>
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
            <.icon name="x" />
          </button>
        </div>
      </div>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div
      id={"#{@id}-wrapper"}
      phx-hook="Brando.BlockField"
      hidden={@hidden}
      class={["blocks-wrapper", @note_collection? && "footnote-storage", @source_locked && "is-source-locked"]}
      data-block-field={"#{@form_name}[#{@block_field}]"}
      data-entry-id={@entry.id}
      data-paste-allow={Block.Render.paste_allow(@clipboard_meta)}
    >
      <div :if={!@note_collection?} class="label-wrapper">
        <label class="control-label" data-field-presence={"#{@form_name}[#{@block_field}]"}>
          <span>{gettext("Blocks")}</span>
          <div class="field-presence" phx-update="ignore" id={"#{@form_name}[#{@block_field}]-field-presence"}></div>
        </label>
        <%!-- With blocks, Build with AI sits by the label; an empty field
              offers it in its card instead, so it is never shown twice. --%>
        <div :if={@assistant? && @root_order != []} class="block-field-assistant">
          <span :if={@entry.id && @blocks_changed?} class="block-field-assistant-hint">
            {gettext("The assistant reads the saved entry, without your unsaved changes")}
          </span>
          <span :if={!@entry.id} class="block-field-assistant-hint">
            {gettext("Save the entry to build it with AI")}
          </span>
          <AIAction.button
            :if={@entry.id}
            href={assistant_url(@entry, @block_field)}
            target="_blank"
            rel="noopener"
            size={:compact}
            data-testid="build-with-ai"
          >
            {gettext("Build with AI")}
          </AIAction.button>
          <AIAction.button :if={!@entry.id} size={:compact} disabled data-testid="build-with-ai">
            {gettext("Build with AI")}
          </AIAction.button>
        </div>
      </div>
      <p :if={@source_locked} class="blocks-source-note">
        {gettext("Blocks, their order and media follow the source. Edit the text here.")}
        <.link :if={@source_url} navigate={@source_url}>{gettext("Change structure in the source")}</.link>
      </p>
      <div class={["blocks-content", @root_order == [] && !@note_collection? && !@source_locked && "is-empty"]}>
        <div :if={!@note_collection? && (@root_order != [] or @clipboard_meta)} class="blocks-actions">
          <div class="block-field-dropdown">
            <button
              type="button"
              class="block-field-dropdown-toggle"
              data-ui-dropdown-toggle={"block-field-#{@block_field}-actions-dropdown"}
            >
              <.icon name="circle-ellipsis" />
            </button>
            <ul
              class="block-field-dropdown-content hidden"
              id={"block-field-#{@block_field}-actions-dropdown"}
            >
              <%= if @root_order != [] do %>
                <li>
                  <button
                    type="button"
                    phx-click={
                      JS.push("rebuild_outline", target: @myself)
                      |> toggle_drawer("#block-field-#{@block_field}-outline")
                    }
                  >
                    <.icon name="text-align-start" /> {gettext("Block outline")}
                  </button>
                </li>
                <li class="dropdown-separator"></li>
                <li>
                  <button
                    type="button"
                    phx-click="collapse_root_blocks"
                    phx-target={@myself}
                  >
                    <.icon name="eye-off" /> {gettext("Collapse root blocks")}
                  </button>
                </li>
                <li>
                  <button
                    type="button"
                    phx-click="expand_root_blocks"
                    phx-target={@myself}
                  >
                    <.icon name="eye" /> {gettext("Expand root blocks")}
                  </button>
                </li>
                <li>
                  <button
                    type="button"
                    phx-click="collapse_multi_children"
                    phx-target={@myself}
                  >
                    <.icon name="eye-off" /> {gettext("Collapse multi blocks")}
                  </button>
                </li>
                <li>
                  <button
                    type="button"
                    phx-click="expand_multi_children"
                    phx-target={@myself}
                  >
                    <.icon name="eye" /> {gettext("Expand multi blocks")}
                  </button>
                </li>
              <% end %>
              <li :if={@clipboard_meta && @root_order != []} class="dropdown-separator"></li>
              <li :if={@clipboard_meta}>
                <button
                  type="button"
                  class="block-field-clipboard-clear"
                  phx-click="clear_clipboard"
                  phx-target={@myself}
                  data-testid="clear-clipboard"
                >
                  <.icon name="clipboard-check" />
                  {gettext("Clear clipboard")}
                  <span :if={@clipboard_meta.label} class="block-field-clipboard-label">
                    {@clipboard_meta.label}
                  </span>
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
        <%= if @root_order == [] && !@note_collection? && !@source_locked do %>
          <section class="blocks-welcome" data-testid="blocks-welcome" aria-labelledby={"#{@id}-welcome-title"}>
            <%= if @templates != [] do %>
              <h3 id={"#{@id}-welcome-title"}>{gettext("Start from a template")}</h3>
              <div class="blocks-welcome-templates">
                <button
                  :for={template <- @templates}
                  type="button"
                  class="blocks-welcome-template"
                  phx-click="start_from_template"
                  phx-value-id={template.id}
                  phx-target={@myself}
                  data-testid="start-from-template"
                  title={Enum.map_join(template.modules, " · ", &(Brando.Type.I18nString.localized(&1.name) || "–"))}
                >
                  <span class="blocks-welcome-stack" aria-hidden="true">
                    <span :for={_block <- Enum.take(template.modules, 5)}></span>
                  </span>
                  <strong>{template.name}</strong>
                  <span :if={template.instructions not in [nil, ""]} class="blocks-welcome-instructions">
                    {template.instructions}
                  </span>
                  <small>
                    {ngettext("%{count} block", "%{count} blocks", template.block_count, count: template.block_count)}
                  </small>
                </button>
              </div>
              <h4 :if={@starting_modules != []} class="blocks-welcome-or">{gettext("Or start with a block")}</h4>
            <% else %>
              <h3 id={"#{@id}-welcome-title"}>{@welcome_title}</h3>
              <p class="blocks-welcome-lead">{@welcome_lead}</p>
            <% end %>

            <div :if={@starting_modules != []} class="blocks-welcome-modules">
              <button
                :for={{tile, index} <- Enum.with_index(@starting_modules)}
                type="button"
                class={["blocks-welcome-module", "is-#{tile.source}"]}
                aria-label={gettext("Start with %{module}", module: ModulePicker.translate(tile.module.name))}
                aria-describedby={starting_module_description(@id, index, tile)}
                phx-click="insert_starting_module"
                phx-value-module={tile.module_ref}
                phx-value-container={tile.container_ref}
                phx-target={@myself}
                data-testid="starting-module"
                data-source={tile.source}
                data-module-ref={tile.module_ref}
                data-container-ref={tile.container_ref}
                data-first-count={tile.count}
                data-of={tile.of}
              >
                <.icon name={ModulePicker.module_icon(tile.module)} />
                <span
                  :if={tile.container}
                  id={"#{@id}-starting-#{index}-container"}
                  class="blocks-welcome-module-container"
                >
                  {tile.container.name}
                </span>
                <span class="blocks-welcome-module-name">{ModulePicker.translate(tile.module.name)}</span>
                <small
                  :if={tile.count}
                  id={"#{@id}-starting-#{index}-count"}
                  class="blocks-welcome-module-count"
                  data-testid="starting-module-count"
                >
                  {gettext("first %{count}/%{total}", count: tile.count, total: tile.of)}
                </small>
                <small :if={tile.source == :used} class="blocks-welcome-module-count">
                  {gettext("often used")}
                </small>
              </button>
            </div>

            <div class="blocks-welcome-actions">
              <button
                type="button"
                class="blocks-welcome-action"
                phx-click={JS.push("show_block_picker", target: @myself)}
                data-ui-modal-show={@module_picker_id}
                data-testid="all-modules"
              >
                <.icon name="plus" />{gettext("All modules…")}
              </button>
              <button
                :if={Block.Render.paste_allow(@clipboard_meta)}
                type="button"
                class="blocks-welcome-action"
                phx-click="paste_block_at_end"
                phx-target={@myself}
                title={@clipboard_meta.label}
                data-testid="paste-first-block"
              >
                <.icon name="clipboard-check" />{gettext("Paste copied block")}
              </button>
              <AIAction.button
                :if={@assistant? && @entry.id}
                href={assistant_url(@entry, @block_field)}
                target="_blank"
                rel="noopener"
                data-testid="build-with-ai"
              >
                {gettext("Build with AI")}
              </AIAction.button>
              <AIAction.button :if={@assistant? && !@entry.id} disabled data-testid="build-with-ai">
                {gettext("Build with AI")}
              </AIAction.button>
              <span :if={@assistant? && !@entry.id} class="blocks-welcome-hint">
                {gettext("Save the entry to build it with AI")}
              </span>
              <span :if={@assistant? && @entry.id && @blocks_changed?} class="blocks-welcome-hint">
                {gettext("The assistant reads the saved entry, without your unsaved changes")}
              </span>
            </div>

            <p :if={@templates == [] && @manages_templates?} class="blocks-welcome-note">
              {gettext("No templates for %{name} yet.", name: Brando.Blueprint.get_plural(@entry.__struct__))}
              <.link href="/admin/config/content/templates" target="_blank" rel="noopener">
                {gettext("Add one in Configuration → Templates")}
              </.link>
            </p>
          </section>
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
                slot_open={@open_slot_uid == block[:uid].value}
                slot_title={@slot_title}
                paste_multi_module_id={@paste_multi_module_id}
                live_preview_active?={@live_preview_active?}
                live_preview_cache_key={@live_preview_cache_key}
                level={0}
              />
            </div>
          </.inputs_for>
        </div>

        <Block.plus
          :if={!@note_collection?}
          click={JS.push("show_block_picker", target: @myself)}
          modal={@module_picker_id}
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
            <.icon name="x" />
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

  defdelegate build_block(module_reference, user_id, parent_id, source, type),
    to: ContentBlocks,
    as: :build_module_block

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
      collapse_multi_children(block_uid, form, collapsed)
    end

    socket
  end

  defp collapse_multi_children(block_uid, form, collapsed) do
    block_cs = Changeset.get_assoc(form.source, :block)
    module_id = Changeset.get_field(block_cs, :module_id)
    module_origin = Changeset.get_field(block_cs, :module_origin) || :local

    if module_id do
      case Brando.Content.fetch_module(module_id, module_origin) do
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

  defp get_module(module_id, origin \\ :local), do: Brando.Content.fetch_module(module_id, origin)

  defp assign_module_set(socket) do
    assign_new(socket, :module_set, fn ->
      %{opts: opts, entry: entry, block_field: field} = socket.assigns

      opts[:module_set] || Brando.Content.Proposals.configured_module_set(entry.__struct__, field) || "all"
    end)
  end

  ## Clipboard helpers

  # The clipboard lives in the cache, keyed by user and tenant — never in the
  # socket — so a block copied in one entry can be pasted into another. Only
  # the *visibility* of the paste buttons was session-local: `clipboard_meta`
  # started nil on every mount, so a freshly opened entry rendered no
  # `data-paste-allow` and CSS hid every paste affordance (see
  # `Block.Render.paste_allow/1`). Reading the cache at init is what makes
  # cross-entry paste reachable.
  #
  # Long enough to copy in one entry, navigate to another (or several) and
  # paste — the previous 15 minute default expired mid-navigation often
  # enough to look like the feature simply did not exist across documents.
  @clipboard_ttl :timer.hours(4)

  defp clipboard_key(user_id), do: {:block_clipboard, user_id}

  defp read_clipboard(user_id), do: Brando.Cache.get(clipboard_key(user_id))

  defp assign_clipboard_meta(socket, %{type: type} = clipboard) do
    socket
    # `label` is fetched rather than matched: a clipboard cached before labels
    # existed is still perfectly pasteable, it just has nothing to name itself.
    |> assign(:clipboard_meta, %{
      type: type,
      parent_module_id: clipboard.parent_module_id,
      label: Map.get(clipboard, :label)
    })
    # Only a copied `module_entry` can change what a `{:multi, module_id}` paste
    # button decides, and that decision is an id comparison CSS cannot make. So
    # it is the one piece of clipboard state that still reaches the block tree —
    # as a scalar, so copying anything else leaves it nil and re-renders nothing.
    |> assign(:paste_multi_module_id, (type == :module_entry && clipboard.parent_module_id) || nil)
  end

  defp assign_clipboard_meta(socket, _no_clipboard) do
    socket
    |> assign(:clipboard_meta, nil)
    |> assign(:paste_multi_module_id, nil)
  end

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

    clipboard = %{
      changeset: changeset,
      type: type,
      parent_module_id: parent_mid,
      label: clipboard_label(type, module_id)
    }

    Brando.Cache.put(clipboard_key(user_id), clipboard, @clipboard_ttl)

    send(
      self(),
      {:toast,
       gettext(
         "“%{block}” is copied. Paste it with the clipboard button beside + between blocks, here or on another page.",
         block: clipboard.label
       )}
    )

    socket
    |> assign_clipboard_meta(clipboard)
    |> then(&{:ok, &1})
  end

  # What the clipboard holds, named at copy time so "clear" can say what it is
  # about to throw away. Snapshotted rather than resolved on read: the module
  # may have been renamed — or deleted — by the time the clipboard is dropped.
  defp clipboard_label(type, module_id) do
    module = module_id && get_module(module_id)

    case module && ModulePicker.translate(module.name) do
      name when is_binary(name) and name != "" -> name
      _ -> block_type_label(type)
    end
  end

  defp block_type_label(:module), do: gettext("Module")
  defp block_type_label(:module_entry), do: gettext("Entry")
  defp block_type_label(:container), do: gettext("Container")
  defp block_type_label(:fragment), do: gettext("Fragment")
  defp block_type_label(_type), do: gettext("Block")

  # A new module block at the root: the module picker's insert, and a starting
  # module's on an empty field.
  defp insert_root_module(socket, module_reference, sequence) do
    {module_origin, module_id} = Brando.Content.SharedLibrary.reference(module_reference)

    block_module = socket.assigns.block_module
    user_id = socket.assigns.current_user.id
    parent_id = nil
    source = socket.assigns.block_module
    empty_block_cs = build_block({module_origin, module_id}, user_id, parent_id, source, :module)

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

    socket
    |> put_seed_form(uid, entry_block_form)
    |> apply_block_op({:insert, uid, sequence, Ops.block_diff_params(entry_block_cs)})
    |> refresh_live_preview()
    |> push_event("b:scroll_to", %{selector: selector})
  end

  # A starting module that usually comes inside a container goes in with it:
  # the container, holding a new block of the module. Inserted as a template's
  # blocks are, so the child reaches the op store with its parent.
  defp insert_root_container_with_module(socket, container_reference, module_reference) do
    {container_origin, container_id} = Brando.Content.SharedLibrary.reference(container_reference)
    user_id = socket.assigns.current_user.id
    source = socket.assigns.block_module

    child_cs = build_block(module_reference, user_id, nil, source, :module)

    container_cs =
      user_id
      |> build_container(nil, source)
      |> Changeset.put_change(:container_id, container_id)
      |> Changeset.put_change(:container_origin, container_origin)
      |> Changeset.put_assoc(:children, [child_cs])

    insert_pasted_root_block(socket, %{changeset: container_cs}, 0)
  end

  defp paste_root_block(socket, sequence) do
    user_id = socket.assigns.current_user.id
    clipboard = read_clipboard(user_id)

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
    block_cs = extract_block_changeset(clipboard.changeset)
    new_uid = Brando.Utils.generate_uid()

    updated_block_cs =
      ContentBlocks.duplicate_block(block_cs,
        user_id: current_user_id,
        sequence: sequence,
        uid: new_uid,
        source: block_module
      )

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

  # `source` is forced to the *target* field's block module: a block copied
  # from a page and pasted into a project would otherwise keep naming the
  # pages join table, and `list_orphaned_blocks/0` reads `source` to decide
  # what a block is still reachable through.
  defp create_duplicate_from_clipboard(clipboard, user_id, block_module) do
    block_cs = extract_block_changeset(clipboard.changeset)
    ContentBlocks.duplicate_block(block_cs, user_id: user_id, source: block_module)
  end

  defp extract_block_changeset(src_changeset) do
    if Map.has_key?(src_changeset.data, :block) do
      Changeset.get_assoc(src_changeset, :block)
    else
      src_changeset
    end
  end
end
