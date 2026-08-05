# Security Audit Phase 2: PubSub topic claim, ref-based finalize, pending intents

Scope: `git diff HEAD~3` (cfb3639fc, d852ec7ef, a3f8a7d35). Threat model:
authenticated admin (or XSS in that context), not anonymous internet. NEW code
only; pre-existing gets one line.

## 1. Client-claimed PubSub topic (D2) — WARNING

**Verdict**: Format-valid (no injection/traversal), but authorization here is
pure security-through-obscurity: nothing checks that the topic actually
belongs to the caller's session/entry, only that it matches `"form:" <> uuid`.

- `Form.handle_event("set_deliver_topic", ...)` (`form.ex:3188`) only calls
  `AssetIntent.validate_deliver_topic/1` (`asset_intent.ex:151`), which checks
  shape only (`"form:" <> valid UUID`). No check that the topic was ever
  minted for *this* socket, user, or entry. Any value of that shape is
  accepted and subscribed to, unsubscribing the form's own mount-time topic.
- Topic is a bare `Ecto.UUID.generate()` (`form.ex:62`), 122 bits of entropy
  — not brute-forceable. So the practical exploit path requires the topic
  leaking (it is rendered client-side as `data-deliver-topic` on the form DOM,
  `form.ex:1901`, and cached in `sessionStorage`, see part 5 below) rather
  than guessing.
- **The receiving side has no defense-in-depth if a topic ever is known**: in
  `hooks.ex:646-682` (`entry_field`) and `:684-724` (`entry_field_gallery`),
  `deliver_asset/3` trusts `target["field"]`/`target["path"]` from the
  broadcast and calls `send_update(Form, id: "#{singular}_form", ...)` —
  `singular` comes from the **receiving** socket's own schema, not from the
  target. There is no check that the target's original schema/entry matches
  the receiving form's schema/entry. In `form.ex`'s
  `entry_field_upload_complete` clauses (`:541-656`) the asset struct is
  written straight into the receiving form's own changeset at `field`/`path`
  with no re-validation that this asset was ever produced for this entry.
  Net effect: whoever's LiveView process is subscribed to a topic receives
  and applies *any* `{:asset_ready, target, asset}` broadcast on it, no
  ownership check, only the topic string gates it.
- **Conclusion**: unguessability is doing all the real work; there is no
  redundant ownership check server-side. That is an acceptable trade-off
  *only* if the topic can never leak to a session that shouldn't have it.
  Given it is written into the DOM and sessionStorage of the tab that owns
  the form, that holds for now, but it means a future XSS or a shared-topic
  bug (see `upload_manager.ex:561-568`, which explicitly documents that a
  remount can already produce topic mismatches) degrades silently into
  cross-entry asset delivery, not an auth error.

**Fix suggestion**: at minimum, log/reject when a delivered `target`'s
recorded entry/schema doesn't match the receiving socket's
`assigns.entry.id`/`assigns.schema`, so a topic collision or leak fails
loudly instead of silently misfiling an asset into the wrong entry.

## 2. Client-supplied ref finalizing an upload (D1) — WARNING

**Verdict**: `key`/`resolved_target` used for finalize are always server-side
(never trusts the ref's caller for those), so no forged/replayed ref can
finalize an object it didn't presign, and replay-into-duplicate is guarded.
But `finalize_orphaned_complete/3` finalizes using the **calling socket's**
`current_user`, never checking it against `intent.creator_id` — a real
creator-attribution gap, gated in practice by the ref being an unguessable
UUID.

- Live-item path (`upload_manager.ex:111-153`): a replayed `ref` against an
  already-`:done` item is a no-op (`:117`) — no duplicate asset. A `ref` for
  a different transport is rejected and logged (`:146-152`).
- Orphan/recovered path (`:143`, `finalize_orphaned_complete/3` at `:507`):
  when no in-memory item matches, it loads `Uploads.get_pending_intent(ref)`
  — a **global** lookup keyed only by `ref` (`uploads.ex:170`), not scoped to
  `socket.assigns.current_user`. It then calls
  `finalize_item(item_from_intent(intent), user)` where `user` is
  `socket.assigns.current_user` of the *requesting* socket — **not**
  `intent.creator_id`. `finalize_direct/3` (`uploads.ex:254-302`) passes this
  `user` straight to `Brando.Upload.handle_upload_type/3` as the asset's
  creator.
  - Practical effect: if admin B ever learns admin A's pending `ref` (e.g.
    via a leaked log line, a shared support session, or the topic-mismatch
    scenario the code itself documents at `upload_manager.ex:561-568`) and
    fires `direct_complete` with that ref on B's own socket before A's
    upload completes or the reaper sweeps it, the resulting asset is created
    with `creator_id = B`, not A, silently misattributing authorship. It is
    still *A's* uploaded bytes (key/resolved_target are A's, from the
    intent) — so this is a misattribution/audit-trail bug, not an
    arbitrary-file-read/write, and it requires already knowing another
    admin's unguessable `ref` (also a raw 128-bit UUID, `uploads.ex:170-174`
    validates via `Ecto.UUID.cast/1`).
  - **Comment in the code itself flags this exact question** (`upload_manager.ex:133-142`)
    but only reasons about *availability* ("recover the asset"), not about
    *whose* identity finalizes it. No `intent.creator_id == user.id` check
    exists anywhere in this path.
- `direct_error` and `cancel_item` both delete the intent
  (`upload_manager.ex:164`, `:232`) before any object necessarily exists in
  the bucket — comment at `:160-163` correctly identifies this as closing
  the "forged `direct_complete` finalizes a half-written object" hole, and
  it does: once the intent is gone, `get_pending_intent` returns `nil` and
  `finalize_orphaned_complete` just logs and no-ops (`:509-515`). A
  half-written object left behind is the reaper's problem, consistent with
  the module's stated design.
- Minor race (not exploitable, noted for completeness): two concurrent
  `direct_complete` calls for the same orphaned `ref` before
  `delete_pending_intent` completes could both pass `get_pending_intent` and
  both call `finalize_item`, producing two asset rows for one object. Low
  severity — requires the same already-hard-to-obtain unguessable ref twice
  in a race window.

**Fix suggestion**: in `finalize_orphaned_complete/3`, either finalize with
`intent.creator_id` (fetch the actual user) instead of the calling socket's
`current_user`, or explicitly reject when they differ and log it as a
suspicious cross-user finalize attempt.

## 3. `uploads_pending_intents` table + `CDN.delete_object/2` — OK (no injection/traversal in `key`)

**Verdict**: confirmed — `key` is 100% server-generated at presign time and
never accepted from client params for storage or deletion.

- `record_pending_intent/4` (`upload_manager.ex:445-456`) writes
  `key: direct.key`, where `direct` is the tuple returned by
  `Uploads.initiate/4` → `initiate_direct_asset/3`
  (`uploads.ex:387-409`): `key = Path.join(["media", cfg.upload_path,
  filename])`, with `filename` built by `build_direct_filename/2`
  (`uploads.ex:414-426`, pre-existing, unchanged by this diff) from the
  client's original filename run through `slugify_filename`/`unique_filename`/
  `random_filename` + `ensure_correct_extension`. The client never supplies
  `key` directly to `create_pending_intent/1` or to `CDN.delete_object/2` —
  the reaper (`upload_intent_reaper.ex:57-58`) reads `intent.key` straight
  from the DB row, which only intake ever wrote.
- `PendingIntent` schema (`pending_intent.ex`) has no changeset path that
  lets `key` be set from arbitrary attrs supplied by a request handler other
  than `record_pending_intent/4`'s hardcoded map — no controller/LiveView
  event forwards a client `"key"` param into this table.
- One pre-existing note (not in this diff, one line per scope): if
  `cfg.slugify_filename` is false, the client's original filename string
  (including any `/`/`..` characters) flows into `build_direct_filename`
  largely intact before `unique_filename` appends a hash — but the sink is
  an S3-compatible object key (`ExAws.S3.delete_object/put`), which is a
  flat namespace where `..`/`/` are just characters, not filesystem
  traversal, so this is not exploitable against S3-compatible backends. Not
  reassessed for any non-S3 storage adapter.
- `target` (jsonb, includes `deliver_topic`) is stored and later trusted
  verbatim for delivery (`upload_manager.ex:569-572`,
  `deliver/2` broadcasts to `target["deliver_topic"]`) — this is the same
  server-minted topic from part 1, not client-reachable at this table, so no
  new issue here beyond what's flagged in section 1.

## 4. `sessionStorage` topic in `assets/src/hooks/Form/index.js` — SUGGESTION

Not fully assessed (time-boxed). Established: the hook stores the
`"form:" <> uuid` topic in `sessionStorage`, keyed per-tab and per-entry
(`index.js:134-166`), and replays it via `pushEventTo(..., 'set_deliver_topic', ...)`.
`sessionStorage` is per-origin and per-tab, not shared cross-origin, so a
same-origin XSS anywhere in the admin already has equivalent DOM/session
access and this adds no incremental capability beyond what section 1 already
covers (reading `data-deliver-topic` directly). No additional leak vector
identified (no `postMessage`, no third-party script access observed in the
diff). Did not check whether any other hook/vendor script reads
`sessionStorage` broadly.

## Not reached / NOT ASSESSED

- Did not re-verify `Brando.Upload.handle_upload_type/3` internals for how
  `creator_id` is actually persisted from the `user` argument (assumed
  standard from naming/usage, not read in this pass).
- Did not check for rate limiting on `direct_complete`/`intake` (could allow
  an admin to hammer `get_pending_intent` — low severity, authenticated
  surface only).
- Did not check e2e/test coverage for these three paths.

## Priority

1. **WARNING** — D1 creator misattribution: use `intent.creator_id`-aware
   finalize instead of trusting the calling socket's `current_user`.
2. **WARNING** — D2 missing redundant ownership check on asset delivery
   receipt (currently relies solely on topic secrecy).
3. **SUGGESTION** — document/confirm no non-S3 storage adapter is exposed to
   the pre-existing filename-to-key path.

No BLOCKER found. All three issues require either an already-hard-to-obtain
unguessable identifier (topic or ref) or are latent (fail loud vs. fail
silent) rather than directly exploitable today.
