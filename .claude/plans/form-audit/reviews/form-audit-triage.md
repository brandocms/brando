# Phase 4 Triage — form-audit

**Source review:** `.claude/plans/form-audit/reviews/phase-4-review.md`
**Date:** 2026-08-06
**Outcome:** 15 approved · 0 skipped · 0 deferred

All findings approved. No Iron Law auto-inclusions (all iron-law findings were
pre-existing code outside the diff). Three approach decisions captured below.

---

## Fix Queue

### Production code

- [ ] **W1 — translate the 404 into the documented contract**
      `lib/brando/cdn/client.ex` (`Client.ExAws.head_object/3`)
      **Decision: translate in the impl**, keeping `client.ex:44`'s documented
      `{:error, :not_found}` and making `uploads.ex:282` reachable.

      ```elixir
      def head_object(bucket, key, s3_config) do
        bucket
        |> ExAws.S3.head_object(key)
        |> ExAws.request(s3_config)
        |> case do
          {:error, {:http_error, 404, _}} -> {:error, :not_found}
          other -> other
        end
      end
      ```

      This makes the mock and the real client agree, so
      `direct_finalize_test.exs:130` stops asserting a shape only the mock can
      emit. **Mutation-verify**: revert the translation and confirm the test goes
      RED — it currently passes against the broken client, which is the whole
      defect. Note this puts one `case` into a module whose moduledoc says "thin
      on purpose"; the moduledoc should acknowledge the translation.

- [ ] **W3 — stop `:req_options` outranking the auth header**
      `lib/brando/videos/uploaders/mux.ex:575`, `bunny.ex:433`, and
      `cloudflare.ex:283` (pre-existing, same shape — fix all three together).
      Reverse to `Keyword.merge(req_options(), request_opts)` so the built
      URL/method/auth headers win. Every test sets only `plug:`
      (`provider_client_test.exs:52`), so nothing should break — confirm by
      running `provider_client_test.exs`.

- [ ] **S — finish enforcing `uid`**
      `content_blocks.uid` is still nullable (`test_migrations.exs:296`), and
      `reject_deleted` runs only in the save path, not validate. Decide whether
      the DB-level `null: false` belongs in the fixture migration alongside the
      existing `validate_required(:uid)`.

- [ ] **S — namespace the upload-manager form id**
      `lib/brando_admin/live/upload_manager.ex:647` —
      `id="upload-manager-queue-form"` is unprefixed in a library. No in-repo
      collision; `validate_queue` ignores params so recovery is a no-op.

### Test harness

- [ ] **W2 — restore `trap_exit`, narrow `flush_exits/0`**
      `test/support/live_case.ex:100,113-120`. Capture the prior flag and restore
      it after the kill; drain only the killed proxy's `{:EXIT, pid, _}` rather
      than every exit for 50ms. Flagged independently by two agents.
      **Mutation-verify**: assert that a deliberately-broken second mount now
      fails the test rather than passing silently — that is the failure mode this
      leak hides, and it lives in the file written to prove recovery works.

- [ ] **W6 — model selects the way a browser submits them**
      `test/support/live_case.ex:219-227` — `selected_option/2` returns `[]` where
      a browser submits the first option's value for a single-select with no
      explicit selection. Until this matches, harness recovery params differ from
      real ones and can assert "recovered" for a shape production loses.

- [ ] **W7 — make the tautological assertions capable of going red**
      `test/brando/content/partial_block_save_test.exs:64-73` conflates "no
      errors" with "the block change vanished" — the exact data-loss shape the
      file targets. `partial_block_save_test.exs:203` and
      `asset_orphan_test.exs:48,61` assert Ecto's own behaviour against
      test-invented changesets. Apply the phase's own standard: each must be
      watched going RED against the defect it claims to cover.

- [ ] **S — tie `recovery_target/1` to the installed LiveView**
      It mirrors `view.ts` and correctly catches the `_target` regression today
      (`form_recovery_test.exs:88`, verified mutation-sensitive), but silently
      stops matching if LiveView changes how it picks the recovery target.

### Config, docs, latent traps

- [ ] **W4 — sweep the `put_env(key, nil)` pattern**
      `test/brando/uploads/direct_finalize_test.exs:59` still does
      `put_env(..., original)`. Latent only — masked by `config/test.exs:5`
      guaranteeing a non-nil value. Apply the `fetch_env/2` + `delete_env/2` form
      already correct in `provider_client_test.exs:31,41-42`. Same unswept pattern
      pre-exists at `utils_test.exs:206`, `uploads_test.exs:364`, and
      `html_test.exs:1108` (no restore at all).

- [ ] **W5 — correct the overclaiming comment**
      **Decision: comment only.** `config/test.exs:7` says "Every runtime S3 call
      goes through `Brando.CDN.Client`" — false, since `cdn.ex:311,354,362` still
      call `ExAws.request` directly. `client.ex:11-22` already documents those
      exclusions deliberately, so the design stands; reword the comment to name
      what actually routes through the client (`head_object`, `delete_object`)
      and why the rest does not.

- [ ] **W9 — document the reset requirement**
      **Decision: leave the index as-is, document it.** No dedupe step;
      `priv/repo/migrations/20260806000001_unique_block_uid_in_test_schema.exs`
      is fixture-only and e2e always runs `--reset`. Add a note in the migration
      that it assumes no pre-existing duplicate uids, so a future non-reset run
      has an explanation rather than a raw Postgres error.

- [ ] **S — decide on `config`/`test` in the hex package**
      `mix.exs:75-86`. Harmless today (a dep's config is never evaluated by
      consumers; all values are placeholders like `String.duplicate("verysecret", 8)`,
      `"TESTKEY"`), but it is a standing invitation for a real key to leak later.

### E2E

- [ ] **W8 — make `goOffline` explicit rather than accidental**
      `e2e/e2e/playwright/utils.js:67`. `socket.js:552` only arms reconnect when
      `closeCode !== 1000`, and `conn.close()` requests exactly 1000 — the helper
      works only because `setOffline` aborts the socket into 1006 first. Use
      `conn.close(4000, …)` so the intent does not depend on ordering.

- [ ] **W10 — close the multiuser-sync race**
      `e2e/e2e/playwright/tests/blocks/block-multiuser-sync.spec.js:103` — B saves
      before waiting to receive A's ship. Surviving `waitForTimeout` removal did
      not make it correct; it made it timing-dependent in the file whose purpose
      was removing timing dependence.

- [ ] **S — trace the suite stdout noise**
      A large `Brando.Blueprint.Forms` struct is inspected to stdout mid-run. Not
      introduced by this diff (leftover grep clean); separate investigation.

---

## Skipped

None.

## Deferred

None.

---

## Verification required before this queue is considered done

Per `AGENTS.md` and the phase's own standard:

1. `mix compile --warnings-as-errors`, `mix format --check-formatted`
2. `mix test` — baseline to hold is **1257 tests / 0 failures**
3. `mix credo --strict` — baseline **284**; any increase must be explained
4. Every behavioural fix (W1, W2, W3, W7) **mutation-verified**: revert the fix,
   watch the test go RED, restore. Watching a test go green proves nothing.
5. E2E items (W8, W10) need `cd e2e && source .envrc && ./test_e2e.sh --reset`
   against rebuilt consumer assets — baseline **108 passed / 0 failed**. Run the
   two named specs individually first.

## Pre-existing, explicitly NOT in this queue

Carried from the review for the record: `form.ex:6287,6315,6343`
(`String.to_integer` on client params, raises during reconnect →
reconnect loop), `form.ex:6294…6459` (`String.to_existing_atom` raising),
`upload_manager.ex:492-505` (bare catch-all rescue), `asset_intent.ex:143,182`
(the two credo warnings). `cloudflare.ex:283` is the one pre-existing item
pulled *into* the queue, since W3 fixes its siblings and leaving it inconsistent
would be worse.
