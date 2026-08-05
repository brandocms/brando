# Ecto review — Form audit Phase 2 (cfb3639fc, d852ec7ef, a3f8a7d35)

Ash not detected (plain Ecto app). Scope: new code only.

## 1. `Brando.Uploads.PendingIntent` + migrations

- **Plain `Ecto.Schema` call is right.** Minutes-long transport bookkeeping, no
  admin listing/identifier, no soft delete needed for a row that must actually
  disappear on reap — a Blueprint (with its soft-delete/listing machinery)
  would fight that requirement. Good call, well justified in the moduledoc.
- Migration and upgrade template are in step (types, nulls, both indexes,
  `on_delete: :nilify_all` for `creator_id`) — verified byte-for-byte modulo
  comments/moduledoc. Good.
- `null: false` on `ref`/`key`/`resolved_target`/`asset_type` matches
  `@required` in the changeset. `mime_type`/`filename`/`filesize`/`target`
  nullable/optional metadata — consistent.
- `target :map` + `jsonb` default `"{}"` is the correct pairing for an opaque
  JSON blob that's never queried by sub-field — fine.
- `ref` as a separate unique `Ecto.UUID` column rather than the PK is
  justified: keeps the integer PK for the FK/join path, and `ref` is the only
  handle a `direct_complete` payload carries — a client-supplied value should
  not double as the database's clustering/PK column.
- **Real gap (new code):** no `@timestamps_opts [type: :utc_datetime_usec]`,
  so this table silently gets `:naive_datetime` timestamps — a deviation from
  the project's own new-table convention (and from `AssetIntent`/other new
  schemas in this repo). `list_stale_pending_intents/1` compares against a
  `NaiveDateTime` cutoff so it's *internally* consistent, just off-convention.
  Low stakes given the table's lifetime, but worth a one-line fix.
- `creator_id` correctly omits an explicit `:type` — `Brando.Users.User` uses
  the default integer PK, no `@foreign_key_type` mismatch.

## 2. `Brando.Uploads` context functions

- `get_pending_intent/1`'s `Ecto.UUID.cast/1` guard is correct and necessary —
  `get_by(PendingIntent, ref: ref)` with a non-UUID string raises
  `Ecto.Query.CastError` given `ref`'s Ecto type; this pattern-matches the
  concern precisely.
- `delete_pending_intent/1` (struct) vs `delete_pending_intent/1` (ref) two
  clauses are clean; ref-not-found returns `{:ok, :not_found}` rather than an
  error tuple — reasonable for an idempotent cleanup call site (reaper, error
  path), but callers must know not to pattern-match bare `{:ok, _}` gets result
  vs error — fine here since only internal callers use it.
- Minor TOCTOU: ref-based delete does a `get` then `delete`; a concurrent
  finalize+delete of the same row between the two calls would raise
  `Ecto.StaleEntryError` from `Repo.delete`. Not exercised today (each intent
  has exactly one plausible actor at a time — the browser or the reaper, and
  the reaper only reaps after `@stale_after_hours`), but there's no rescue if
  that assumption ever breaks.
- `create_pending_intent/1` / `list_stale_pending_intents/1` are straightforward
  and correct.

## 3. `processing_queued?/1`

- Query logic is correct: `worker == ^worker and state in ^states and
  fragment("? @> ?", args, ^%{image_id: image_id})`, `select: true, limit: 1`,
  `one/1 == true` — a sound `exists?` substitute given `Brando.Repo` has none.
- The `fragment("? @> ?", j.args, ^map)` pattern is copied from the
  pre-existing `queue_processing/4` a few lines above (unchanged in this
  diff), so the jsonb-param encoding already works in this codebase — no new
  risk introduced.
- Not indexed: Oban's Postgres migration only adds a partial index on
  `(state, queue, priority, scheduled_at, id)`, nothing on `args` (no GIN).
  The `worker`+`state` filters narrow via that partial index before the
  containment check runs as a residual filter, which is fine at normal
  `image_processing` queue depths; flag only if that queue is ever expected to
  carry a large `available`/`retryable` backlog.

## 4. `Brando.Galleries.merge_loaded_media/2`

- `NotLoaded` handling is correct: `loaded_media?/1` requires both a non-nil
  FK id *and* `Brando.Utils.loaded_assoc?/2` true (which itself treats
  `%Ecto.Association.NotLoaded{}` and `nil` alike as "not loaded") before
  trusting the object's own association.
- `same_media?/2` → `matches?/3` correctly refuses to match on `nil == nil`
  (explicit `{nil, _} -> false` / `{_, nil} -> false` clauses before the
  `{same, same}` catch-all), so two objects that both lack an `image_id` don't
  spuriously "match" and borrow each other's unrelated media.
- Object with neither `image_id` nor `video_id` loaded and no previous match
  falls through to `|| object`, returned unchanged — correct, no crash.

## Pre-existing (one line each)

- `Brando.Images.Processing` recreate_sizes_for_image_field/2 duplicates ~15
  lines with the `"default"` clause above it verbatim.
- `Brando.Galleries.list_gallery_asset_usage/1` builds `field_atom` via
  `String.to_existing_atom` off a stored `config_target` string — fine (not
  user input), pre-existing pattern.
