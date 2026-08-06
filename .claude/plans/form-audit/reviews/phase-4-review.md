# Phase 4 Review — LiveView test harness + the fixes it exposed

**Scope:** `HEAD~5..HEAD` on `next` (5 commits, 1956 insertions / 73 deletions, 24 files)
**Agents:** elixir-reviewer, testing-reviewer, iron-law-judge, security-analyzer,
verification-runner, requirements-verifier
**Date:** 2026-08-06

## Verdict: PASS WITH WARNINGS

No production-breaking blocker. All gates green. Every finding below was
re-verified by hand against the source before landing here — three agent
findings were downgraded and three were reclassified as pre-existing.

---

## Requirements Coverage

**Source:** `.claude/plans/form-audit/plan.md` Phase 4 (lines 1036-1221)

| | Count |
|---|---|
| MET | 4 |
| MET-WITH-DEVIATION | 3 |
| PARTIAL | 0 |
| UNMET | 0 |
| UNCLEAR | 0 |

No verdict escalation (no UNMET, no PARTIAL).

The three deviations are the items the author flagged as "wrong as written."
Each stated justification was checked against the artifact it cites, not taken
on the author's word — **all three hold**:

- **Asset cleanup not implemented as asked** — `docs/UPLOADER.md` §7 and
  `research/03-uploads.md` §1.2 both already record unreferenced assets as
  accepted-by-design orphans with no GC. The original item asked for a
  guarantee the system never made.
- **No positive reload-recovery assertion** — `assets/src/hooks/BlockField/index.js:53-61`:
  `mounted()` is an explicit no-op, capture is in `disconnected()`, replay in
  `reconnected()`. A reload runs neither, so the requested assertion is
  structurally impossible.
- **Two seams instead of one** — `lib/brando/uploads.ex:474` confirms
  `ExAws.S3.presigned_url/5` is a local HMAC, not a network call.

**One overstatement to correct** (prose only, nothing falsely checked): the
status note claims all three deferred E2E items are "addressed by the harness's
existence." That holds for B1 and C1. It does **not** hold for **B5** —
conditional/looped ref regions have no relation to process death, and nothing
in this diff touches them. All three correctly remain `- [ ]`.

---

## Verification Gates — all PASS

| Gate | Observed |
|---|---|
| `mix compile --warnings-as-errors` | exit 0 |
| `mix format --check-formatted` | exit 0 |
| `MIX_ENV=test mix test` | **135 doctests, 1257 tests, 0 failures** (12.5s) |
| `mix credo --strict` | **284** (2 W / 118 R / 152 Rd / 12 D) — matches baseline |
| `git diff --check` | clean |
| debug-leftover grep | zero matches |
| E2E Playwright | NOT RUN (author reports 108/0; unverified here) |

Both credo `[W]` warnings sit in `lib/brando/uploads/asset_intent.ex:143,182` —
outside this diff, pre-existing. The claimed 1257/0 and 284 both confirmed
exactly. The "+35 tests" delta was not independently baselined.

---

## WARNINGS

### W1. The `{:error, :not_found}` contract is documented, tested, and never produced
`lib/brando/cdn/client.ex:44` · `lib/brando/uploads.ex:282` · `test/brando/uploads/direct_finalize_test.exs:130`

`client.ex:44` documents:

```elixir
@doc "Fetch object metadata. `{:error, :not_found}` when the key is absent."
```

`Client.ExAws.head_object/3` is a pass-through with no translation, and ExAws
returns `{:error, {:http_error, status, error}}` for a missing key
(`deps/ex_aws/lib/ex_aws/request.ex:164`, `client_error/2`). So `:not_found`
is never emitted by the real client.

Consequences, verified:
- `uploads.ex:282`'s `{:error, :not_found} -> {:error, "Uploaded object not found in bucket (#{key})"}`
  branch is **unreachable in production**; a genuinely missing object falls to
  `{:error, reason}` and reaches `upload_manager.ex:129` as
  `inspect({:error, {:http_error, 404, %{...}}})`.
- The test that covers it stubs the documented shape directly, so it passes
  against a client that can never produce it. Its own comment states the intent
  — "the message has to name the key so an operator can find the gap between
  the intent and the bucket" — which is exactly what is lost.

No crash and no data loss: impact is an opaque log line on an already-failing
upload, plus false test confidence. This is the same shape as the phase's own
recurring finding — *a declared contract the implementation does not honour*.

### W2. `kill_live/1` leaks `trap_exit`, and `flush_exits/0` over-drains
`test/support/live_case.ex:100,113-120` — *flagged independently by two agents*

```elixir
Process.flag(:trap_exit, true)
Process.exit(pid, :kill)
```

The flag is never restored. ExUnit's per-test process prevents cross-test
bleed, but every recovery test **re-mounts after** `kill_live/1`
(`form_recovery_test.exs:53,76,100`), and `live/2` links the test to the client
proxy. A crash in that second mount now arrives as a message instead of failing
the test — i.e. a test can go green against a LiveView that never mounted.
`flush_exits/0` compounds it by draining *every* `{:EXIT, _, _}` for 50ms, not
just the killed proxy's.

### W3. `:req_options` config outranks the auth header and URL it is merged into
`lib/brando/videos/uploaders/mux.ex:575` · `bunny.ex:433` — *flagged independently by two agents*

```elixir
request_opts = Keyword.merge(request_opts, req_options())
```

`Keyword.merge/2` lets the right side win, and `request_opts` is what carries
the Mux Basic auth header and the Bunny `AccessKey`. A configured `url:` would
send live credentials to an arbitrary host; `connect_options: [transport_opts: [verify: :verify_none]]`
would disable TLS on the credentialed call.

Not remotely exploitable — config is trusted input — but it is **new surface**:
no config key could reach those headers before this diff. Every test sets only
`plug:` (`provider_client_test.exs:52`), so reversing to
`Keyword.merge(req_options(), request_opts)` breaks nothing.
`cloudflare.ex:283` has the identical shape and predates this diff, so the new
code faithfully copied an existing pattern; the fix belongs in all three.

### W4. The `put_env(key, nil)` lesson was applied where it bit, not swept
`test/brando/uploads/direct_finalize_test.exs:59`

The phase's own scratchpad records: *"`Application.put_env(key, nil)` is not the
same as absent."* The fix landed correctly in `provider_client_test.exs:31,41-42`
(`fetch_env/2` + `delete_env/2`), but a file shipped in the **same phase** still does:

```elixir
original = Application.get_env(:brando, Brando.Files)
on_exit(fn -> Application.put_env(:brando, Brando.Files, original) end)
```

This cannot fail today only because `config/test.exs:5` guarantees a non-nil
value — a latent trap, not an active bug. Downgraded from the reporting agent's
BLOCKER for that reason. The same unswept pattern exists pre-existing at
`utils_test.exs:206`, `uploads_test.exs:364`, and `html_test.exs:1108` (no
restore at all).

### W5. `config/test.exs:7` overclaims the boundary
`config/test.exs:7`

> "Every runtime S3 call goes through `Brando.CDN.Client`"

False as written: `cdn.ex:311` (`s3_upload/7`, Oban-driven), `cdn.ex:354` and
`cdn.ex:362` (`ensure_bucket_exists/1`) still call `ExAws.request` directly.
Nothing reaches a bucket in test only because `cdn: enabled: false`.

Mitigating and worth stating: `client.ex:11-22` **deliberately documents** these
exclusions ("bulk operations… move real bytes; a stub proves nothing about
them"). The behaviour's design is coherent — only the config comment overstates
it. Doc accuracy, not a design flaw.

### W6. Harness recovery params don't model how a browser submits selects
`test/support/live_case.ex:219-227`

`selected_option/2` returns `[]` when no `<option selected>` is present, but a
browser submits the **first** option's value for a single-select with no
explicit selection. Recovery params built by the harness therefore omit selects
that a real recovery includes — so the harness can assert "recovered" for a
field shape production actually loses, in the one file written to prove
recovery works.

### W7. Assertions that cannot go red
`test/brando/content/partial_block_save_test.exs:64-73,203` · `test/brando/uploads/asset_orphan_test.exs:48,61`

- `partial_block_save_test.exs:64-73` conflates "no errors" with "the block
  change vanished" — the precise data-loss shape the file exists to catch.
- Three assertions (`asset_orphan_test.exs:48,61`, `partial_block_save_test.exs:203`)
  test Ecto's own behaviour against test-invented changesets and cannot fail for
  any Brando change.

Given the phase's own standard — every fix mutation-verified by watching it go
RED — these are the assertions that standard would reject.

### W8. `goOffline` works by accident of close-code
`e2e/e2e/playwright/utils.js:67`

`socket.js:552` only arms reconnect when `closeCode !== 1000`, and `conn.close()`
requests exactly 1000. The helper works today only because `setOffline` aborts
the socket into 1006 first. A `conn.close(4000, …)` would make the intent
explicit rather than order-dependent.

### W9. Unique index has no dedupe step, against a long-lived e2e DB
`priv/repo/migrations/20260806000001_unique_block_uid_in_test_schema.exs`

Both migrations are reversible with correct constraint names. But the unique
index on `content_blocks.uid` has no pre-dedupe, and the migrations dir is
**symlinked into e2e** — a long-lived DB that has been running without the
constraint. It will fail to migrate if duplicates exist. Clean on a `--reset`
run, which is how it was validated.

### W10. E2E race
`e2e/e2e/playwright/tests/blocks/block-multiuser-sync.spec.js:103`

Client B saves before waiting to receive A's ship. Surviving `waitForTimeout`
removal doesn't make it correct — it makes it timing-dependent in a file whose
whole point was removing timing dependence.

---

## SUGGESTIONS

- **`validate_required(:uid)` is only half-enforced.** Applied symmetrically to
  both changesets and safe across deleted children, partial saves, and
  duplication (`blocks.ex:1053` supplies uids). But `content_blocks.uid` remains
  nullable (`test_migrations.exs:296`), and `reject_deleted` runs only in the
  save path, not validate.
- **`id="upload-manager-queue-form"` is an unprefixed global id in a library.**
  No in-repo collision; `validate_queue` ignores params so recovery is a no-op.
- **`recovery_target/1` mirrors `view.ts` with nothing tying it to the installed
  LiveView version.** It correctly catches the `_target` regression today
  (`form_recovery_test.exs:88` verified mutation-sensitive), but silently stops
  matching if LiveView changes how it picks the recovery target.
- **`mix.exs:75-86` ships `config` and `test` in the hex package.** Harmless —
  a dep's config is never evaluated by consumers, and every value is a
  placeholder (`String.duplicate("verysecret", 8)`, `"TESTKEY"`) — but worth
  knowing before a real key ever lands there.
- **Suite noise:** a large `Brando.Blueprint.Forms` struct is inspected to stdout
  mid-run. Not from this diff (leftover grep clean), worth tracing separately.

---

## Cleared — checked and explicitly NOT flagged

- **No mass-assignment widening from the hoisted assign.** `validate/4` runs
  unconditionally at `form.ex:3038` before and after the change; only the
  `assign` moved out of the branch. The cast is still the whitelisted
  `schema.changeset(params, current_user)`. Anything a crafted
  `_target: ["image_editor_upload"]` reaches was already reachable via
  `_target: [singular, "title"]`.
- **The hoist is behaviourally safe for the `[^singular | rest]` path.**
  Verified by hand: `request_select_options_update/1` reads only
  `form_blueprint`/`singular`; `send_updated_entry_field_to_blocks/4` reads only
  `blocks_wanting_entry`. Neither touches `socket.assigns.form`, so moving the
  assign above them changes nothing.
- Both migrations auto-reversible; all three config reads use runtime
  `Application.get_env/3`, not compile-time.
- `Brando.CDN.Client` Mox usage is correct: behaviour-backed, `expect`,
  `verify_on_exit!`.
- `finalize_direct` genuinely HEADs the object (`uploads.ex:266`) with
  server-side key/mime, plus replay, unknown-ref and cross-user-ref guards —
  the test is not asserting a guarantee the code fails to make.
- No secrets, no float money, no `raw/1`, no atom-key Oban args, pinned Oban
  `fragment`.

---

## PRE-EXISTING (outside this diff — reported for the record, not this phase's debt)

- `form.ex:6287,6315,6343` — `String.to_integer(params["resource_id"])` on
  client-replayed params, guarded only by `id != ""`. Raises during reconnect →
  the recovered LiveView dies → reconnect loop. `Integer.parse/1` into the
  existing no-op branch is the fix.
- `form.ex:6294,6296,6322,6324,6350,6352,6459` — `String.to_existing_atom/1` on
  `params["field"]`/`["schema"]` and each element in `decode_recovery_path/1`,
  which guards only `is_list`. Iron Law #10 is satisfied (not `to_atom`); the
  issue is the raise.
- `upload_manager.ex:492-505` — bare catch-all `rescue`. Defensible for a sticky
  process, but it swallows genuine bugs as per-item upload errors; the real fix
  is upstream in `Brando.CDN.get_s3_config/2` and `cdn.ex:394,411` returning
  rather than raising.
- `cloudflare.ex:283` — same `Keyword.merge` ordering as W3.
- `asset_intent.ex:143,182` — the two credo `[W]` warnings.

---

## Process note

`phx:elixir-reviewer` exhausted its turns and wrote a partial file; it was
resumed via SendMessage and completed all four outstanding items. Logged in
`scratchpad.md` at 13:14. No findings were extracted from chat messages — every
item above traces to a written file plus my own re-verification.

`phx:context-supervisor` was skipped: findings were already compressed and
hand-verified against source, so a summarization pass would only have added
lossy indirection.
