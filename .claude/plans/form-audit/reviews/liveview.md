# LiveView correctness review — commit 2c26cb31b

Scope: the 8 changed files listed in the task. Static analysis only (no Bash
tool available in this session, so `git diff HEAD~1` was read via file
inspection rather than executed directly).

## 1. `render.ex` `carried_refs/1` — second `inputs_for` over `refs`

`carried_refs/1` and `ref/1` both call `<.inputs_for field={@block_form[:refs]}>`
on the same association, but they are **mutually exclusive by construction**:
`ref/1` renders only when `ref_form[:name].value == @ref_name` (one name per
call, driven by `liquid_splits`); `carried_refs/1` renders only when
`ref_form[:name].value not in rendered_names` (the complement, computed as
`for {:ref, name} <- liquid_splits`). For a given ref index, exactly one of
the two branches is truthy, so there's no duplicate DOM id or duplicate input
`name=` collision, and `_persistent_id={ref_form.index}` is set identically
to what LiveView's default would compute anyway — not a new hazard.

**Pre-existing, unrelated to this diff (one-liner):** if the same ref name
appears twice in `liquid_splits` (module code references `refs.x` twice),
`ref/1` is invoked twice and renders the same `id="block_ref-#{uid}"`
section and the same input names twice — duplicate DOM ids. Not introduced
here; not investigated further.

## 2. `render.ex` `ref/1` — FK hidden inputs now unconditional

Moved `image_id`/`video_id`/`gallery_id`/`file_id` out of the
`ref_form[:id].value in [nil, ""]` guard so they always render. Checked for
collision with a nested block's own picture-block fields: the ref-level FKs
use `ref_form[:image_id].name` (path `..refs][N][image_id]`), while a nested
picture block's own image field lives under the polymorphic `data` (path
`..refs][N][data][image_id]`) — different form paths, no name collision.
`restore_programmatic_ref_media/2` and `restore_ref_media_params/2` in
`events.ex` (the steady-state counterpart) match by ref `id`, `put_new`
params so DOM-carried values win, consistent with the doc comment. This
matches the scratchpad's Phase-0 plan (option a+b) and looks correctly wired
now (previously flagged as "half-implemented" in scratchpad — now complete).

## 3. `form.ex` `commit_selected_asset/3` inside `update/2`

`commit_selected_asset` is guarded: it only fires `commit_entry_field_asset`
(push_event + ship_all_field_changes) when `edit_asset.field` is non-nil
**and** `edit_asset.block_target` is absent — block-level picks are excluded
by an explicit `if Map.get(edit_asset, :block_target)` short-circuit
(`form.ex:1177-1183`), consistent with the comment that block picks commit
via `Block.commit_ref_data/2` instead. Traced one concrete caller,
`input/video.ex`'s `select_video` handler → `send_update(Form, action:
:update_edit_video, video: video)` → matches `form.ex:289-301` → merges into
existing `edit_video` (which carries `field:` from the earlier
`open_video_drawer` round-trip) → commits. This is the entry-field picker
path, not a block ref pick, so it's the intended target. Running a `push_event`
+ multi-user ship from `update/2` rather than `handle_event/3` is unusual but
not unsafe per se — `update/2` still runs in the component process, so
`push_event`/`assign` are safe there. Did not fully trace the image-editor
save path (`form.ex:3453`, `:3543`) or `input/file.ex`'s two call sites
against this guard to rule out a double-commit; see "Not investigated."

## 4. `block.ex` `extract_child` ↔ `block_field.ex` `insert_extracted_child`

Verified. Sender (`block.ex:190-219`, the `extract_child` update clause)
sends `%{event: "insert_extracted_child", target_parent_uid: target_uid,
child_uid: uid, sequence: seq}`. Receiver (`block_field.ex:263-266`) matches
`%{event: "insert_extracted_child", target_parent_uid: target_uid, child_uid:
uid, sequence: seq}` — exact key match, no mismatch. Grepped for all
occurrences of `insert_extracted_child` / `extract_child` in `lib/`: exactly
one sender (`block.ex:215`) and one receiver (`block_field.ex:264`) for
`insert_extracted_child`, and one sender (`block_field.ex:1146`, presumably
the outline drag handler) and one receiver (`block.ex:191`) for
`extract_child`. No other caller was missed. The contract is sound; the
comment on both sides correctly documents *why* only `child_uid` travels now
(the old `child_changeset:` payload carried a stale mount-time seed and
discarded live edits — `block_field.ex` now rebuilds via
`Ops.materialize_child/2` from the op store instead).

## 5. `block_field.ex` `materialize_child` failure branch — WARNING

**Real inconsistency, worth flagging.** On `insert_extracted_child`, the
*sender* (`block.ex`'s `extract_child` clause) unconditionally and
optimistically removes the child from ITS OWN local `block_list` /
`changesets` / `children_forms` assigns before sending the message — this is
a separate live_component process from `block_field.ex` and has no
rollback path. `block_field.ex`'s error branch only logs and calls
`rebuild_outline_items(socket)`, which rebuilds `outline_items` purely from
`socket.assigns.block_ops` (`Ops.materialize_root/2` over `ops.order`) —
independent of the source Block component's render state. So on
`materialize_child` failure: `block_ops` (canonical store) is untouched,
meaning the *outline* still correctly shows the child under its original
parent — but the *rendered* block, in the source Block component's own
`block_list`, has already vanished from the canvas and is never restored.
Net effect: the block disappears from the live UI (looks deleted to the
user) while surviving server-side in `block_ops`/eventual save. No message
path exists to tell the source Block component "undo the optimistic
removal." This is a genuine UX/consistency bug introduced by this commit's
error branch, not merely "wrong place in the outline."

## Not investigated

- `form.ex` image-editor save path (`:3453`, `:3543`) and `input/file.ex`
  call sites (`:175`, `:199`) against the `commit_selected_asset` guard —
  did not rule out a double-commit or wrong-branch fire from these callers.
- `input/video.ex` beyond `select_video`/`open_video` — no other correctness
  issues spotted in the read, but not adversarially probed against recovery.
- `block/events.ex` `restore_root_ref_media/2` callers — confirmed it exists
  and is symmetric with `restore_programmatic_ref_media/2`, but did not trace
  every call site.
- `subform.ex` and `page_vars.ex` — not reached. Scratchpad claims these were
  the B6 `get_field`→`get_assoc`/`put_assoc` fixes (9 sites); not
  independently re-verified in this pass.
- Duplicate-ref-name-in-liquid_splits DOM-id collision (noted under #1) —
  confirmed pre-existing but not bisected against the parent commit to be
  fully certain it predates this change.
