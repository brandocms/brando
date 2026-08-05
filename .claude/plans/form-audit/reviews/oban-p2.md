# Oban Review: Phase 2 (commits cfb3639fc, d852ec7ef, a3f8a7d35)

## Summary
`UploadIntentReaper` is a reasonable design overall — the "no third party can
still complete this" argument holds — but it silently swallows delete
failures instead of surfacing them to Oban's retry mechanism, and shares a
`limit: 1` queue with user-facing upload workers while doing unbounded,
serial, per-object network calls. `processing_queued?/1` is a sound,
narrowly-scoped mitigation for a real pre-existing race. The test approach
(building an `Oban.Job`/worker changeset and inserting directly, bypassing
`testing: :inline` execution) is correct.

## Iron Law Violations
None of the new code violates idempotency, ID-storage, or return-value laws
outright — see "Issues" below for how return-value handling is actually
undermined in practice.

## Issues Found

### Critical (Must Fix Before Deploy)

- [ ] **`max_attempts: 2` is dead weight — `reap/1` never lets a failure
  reach Oban.** `lib/brando/workers/upload_intent_reaper.ex:51-55,39`:
  `reap/1` always returns `true` regardless of `delete_object/1`'s outcome,
  and `perform/1` unconditionally returns `:ok`. A transient S3 failure
  (network blip, throttling, temporary credential issue) gets exactly one
  delete attempt ever, is logged at `:warning`, and the row is dropped in
  the same pass — Oban's retry/backoff machinery, which `max_attempts: 2`
  implies exists for a reason, is never invoked for the actual failure mode
  this worker exists to handle. Recommend distinguishing "key doesn't exist"
  (already `:ok` per the doc, correctly) from a genuine transport/permission
  error, and either (a) leaving the row for the next sweep on transport
  errors (bounded by a small `meta["delete_attempts"]` counter to avoid the
  every-night-forever case the docstring worries about), or (b) writing the
  undeletable key somewhere durable before dropping the row.

### Warnings

- [ ] **Drop-on-failure loses the only record of a possibly-orphaned
  object**, `lib/brando/uploads.ex:217-228` /
  `upload_intent_reaper.ex:62-69`. The stated rationale (avoid retrying the
  same failure nightly) is reasonable, but the mitigation is "log a warning
  and forget" — logs rotate/aren't queryable for cost or compliance audits.
  Given the sibling `VideoUploadReaper` chose to preserve state
  (`:errored`, not deleted) specifically so nothing gets lost, the
  asymmetry here deserves a second look: even a minimal persisted trail
  (e.g. a `brando_orphaned_uploads` audit row, or re-using the intent table
  with a `failed_at` flag excluded from the stale-list query) would let ops
  reconcile bucket costs later. As-is, an object nobody can locate again
  is the actual worst case this worker can produce.

- [ ] **`:default` queue choice is risky given `limit: 1` and unbounded
  work.** `lib/brando/supervisor.ex:54-57,71` puts `UploadIntentReaper` on
  `:default`, which also carries `FileUploader` and `ImageUploader` —
  interactive, user-facing jobs. `list_stale_pending_intents/1`
  (`lib/brando/uploads.ex:203-207`) has no `limit`, and `reap/1` makes one
  serial network round-trip per row inside a single job with a 5-minute
  `timeout`. With `limit: 1` on `:default`, any large backlog of stale
  intents (bulk abandonment, an outage) will queue-block `FileUploader`/
  `ImageUploader` behind it for up to 5 minutes. `image_processing` already
  has its own queue for exactly this isolation reason — the reaper should
  likely get one too, or at minimum `list_stale_pending_intents/1` should
  take a `limit` and the worker should re-enqueue itself (or rely on the
  next night's cron) instead of trying to drain an unbounded list in one
  job.

- [ ] **No batching/backpressure on `list_stale_pending_intents/1`** —
  covered above; flagging separately because it's independently fixable
  (add a `limit`) even if the queue isn't changed.

### Suggestions

- [ ] Consider logging the S3 key at `:error` (not `:warning`) when a
  delete fails and the row is about to be dropped — right now the only
  trace of a potentially-real orphaned bucket object is a warning-level
  line, easy to miss in aggregated logs.

## Idempotency Assessment

- **`UploadIntentReaper` job-level retry is safe**: `delete_direct_object/3`
  relies on S3 `DELETE`'s natural idempotency (missing key = `:ok`), and
  `delete_pending_intent/1` deleting an already-deleted row is a no-op. If
  the whole job crashes mid-sweep (VM restart, timeout), the next run
  simply re-lists remaining stale rows — no double-charge/double-effect
  risk. The problem isn't retry safety, it's that retries never trigger
  (see Critical above).
- **The "no third party" reasoning holds**: S3 presigned URLs are signature-
  and-expiry enforced server-side by the bucket, not just client-side —
  a browser holding an expired URL genuinely cannot complete the PUT after
  expiry, unlike the video case where a provider webhook is a real actor
  that can arrive independently of any expiry window. The 24h cutoff vs.
  10-minute presign lifetime gives ample margin. This is a materially
  different situation from `VideoUploadReaper` and the contrast in the
  moduledoc is accurate, not just asserted.
- **`processing_queued?/1`**: matches on `image_id` alone across
  `available/scheduled/executing/retryable` states
  (`lib/brando/images/processing.ex:41-70`). The check-then-act window
  between `processing_queued?/1`'s read and the caller's subsequent
  `queue_processing/4` insert is a classic TOCTOU race (two concurrent
  drawer-close saves could both read "false" and both queue), but the
  consequence is only ever a redundant processing pass — not corruption —
  and the caller (`form.ex:4008-4009`) is a single LiveView process per
  drawer, so the realistic window is effectively closed for this call
  site. Good enough for its stated purpose (opportunistic re-queue
  avoidance), not a general-purpose lock.
- **Pre-existing, flagged as one-liner per scope**: `queue_processing/4`'s
  `Repo.delete_all` on jobs matching `args` followed by
  `replace_args: true` insert (`lib/brando/images/processing.ex:22-39`)
  deletes an `executing` job's row out from under its running worker —
  this is a real bug (two passes can write the same derivative files) but
  it's pre-existing and merely worked around, not introduced, by this
  phase's `processing_queued?/1` gate.

## Testing Assessment

- `test/brando_admin/components/form/drawer_close_test.exs:158-219`
  (`describe "(a) processing_queued?/1"`) builds the job via
  `Brando.Worker.ImageProcessor.new/1` (a changeset only, no execution) and
  inserts it directly with `Brando.Repo.repo().insert!/1`, sidestepping
  `Oban.insert/1` entirely. That correctly avoids `testing: :inline`
  running the job inline, and lets the test construct exact job states
  (`available`, `completed`) to exercise `@unfinished_states` filtering.
  Sound approach.
- `test/brando/uploads/pending_intent_test.exs:146,171` constructs
  `%Oban.Job{args: %{}}` in memory and calls `perform/1` directly — this is
  the standard Oban unit-test pattern (equivalent to
  `Oban.Testing.perform_job/2` without the assertion helpers), not a
  database insert; it's fine and doesn't depend on `testing: :inline` at
  all.
