# Phase 5 — Close the Phase 4 review findings

**Source:** `.claude/plans/form-audit/reviews/form-audit-triage.md` (15 approved, 0 skipped, 0 deferred)
**Review:** `.claude/plans/form-audit/reviews/phase-4-review.md`
**Slug:** `form-audit` · **Depth:** standard · **Created:** 2026-08-06

Kept in its own file rather than appended to `plan.md`, which is a living
document whose Phases 0–4 are followed by shared `## Verification` /
`## Sequencing` / `## Risks` sections. Appending Phase 5 after those would break
that structure; overwriting would destroy the phase record.

No research agents spawned — the review findings are the research, and every one
was hand-verified against source during the review.

---

## Baselines to hold

| Gate | Baseline |
|---|---|
| `mix test` | 1257 tests, 0 failures |
| `mix credo --strict` | 284 findings |
| `mix compile --warnings-as-errors` | clean |
| `mix format --check-formatted` | clean |
| E2E (`./test_e2e.sh --reset`) | ~~108~~ **107** passed / 0 failed (see below) |

Any movement in the first two must be explained in `scratchpad.md`, not absorbed.

**The e2e baseline in this table was wrong.** The suite contains 107 tests
(`playwright test --list`: *"Total: 107 tests in 37 files"*), and Phase 5 added
and removed none — `git diff e2e/` touches no `test(` line. The last run this
repo actually recorded was 105/105 (scratchpad, Phase 3 review fixes); 108 was
written into the plan without a run behind it. Final: **107 passed / 0 failed**.

---

## Sequencing rationale

**Phase 5A comes first, and this is the load-bearing ordering decision.** The
harness currently leaks `trap_exit`, so a test can pass against a LiveView that
never mounted. Every *other* task in this plan is verified by watching a test go
RED — which is exactly what a harness with that leak cannot be trusted to
report. Fixing the instrument precedes using it.

5B (production fixes) and 5C (assertions) both depend on 5A. 5D is independent
prose/config. 5E needs a separate environment and is last.

---

## Phase 5A — Make the harness trustworthy `[testing]`

- [x] **W2a — restore `trap_exit` in `kill_live/1`** — **done:** restores the captured flag; nested-safe `test/support/live_case.ex:100`
      Capture the prior flag, restore it after the kill. The flag currently leaks
      for the rest of the test process.

      ```elixir
      def kill_live(view) do
        pid = view.pid
        ref = Process.monitor(pid)
        prior = Process.flag(:trap_exit, true)

        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
        after
          1_000 -> flunk("LiveView #{inspect(pid)} did not exit within 1s")
        end

        flush_exits(pid)
        Process.flag(:trap_exit, prior)
        :ok
      end
      ```

- [x] **W2b — narrow `flush_exits/0` to the killed proxy** — **done:** `await_proxy_exit/1` drains `view.proxy`'s pid only; alive proxy = nothing in flight `test/support/live_case.ex:113-120`
      It currently drains *every* `{:EXIT, _, _}` for 50ms. Take the pid and drain
      selectively so an unrelated linked-process exit is not silently swallowed.
      Note the proxy pid differs from the view pid — drain what `live/2` linked,
      and if the proxy pid is not reachable from `view`, prefer a bounded
      `receive` on the known pid over a blanket catch-all.

- [x] **W2-verify — prove the leak was hiding a real failure** — **done:** throwaway passed against the leak, failed with the fix; deleted, kept a `trap_exit` regression test `[testing]`
      Write a throwaway test that mounts, kills, remounts, and forces the second
      mount to crash. Confirm it **fails** with the fix and **passes** without it.
      This is the mutation-verification for 5A and the justification for its
      position in the sequence. Delete the throwaway afterwards, or keep it if it
      reads as a genuine harness regression test.

- [x] **W6 — model selects the way a browser submits them** — **done:** first option for single-selects, `[]` for `multiple`; 3 serializer tests added `test/support/live_case.ex:219-227`
      `selected_option/2` returns `[]` when no `<option selected>` is present; a
      browser submits the **first** option's value for a single-select. Fall back
      to the first option for single-selects (leave multi-selects returning `[]`,
      which is correct). Until this matches, harness recovery params differ from
      real ones in the file written to prove recovery works.

- [x] **S — tie `recovery_target/1` to the installed LiveView** — **done:** pinned to phoenix_live_view 1.2.8, asserted + named in the docstring `test/brando_admin/live/form_recovery_test.exs`
      It mirrors `view.ts:2450` and catches the `_target` regression today, but
      nothing pins it to the LiveView version. Add a comment naming the mirrored
      source and version, or assert against `Phoenix.LiveView.version()` so a
      bump surfaces the drift rather than silently passing.

**Gate 5A:** `mix test test/brando_admin/live/form_recovery_test.exs` green;
full `mix test` still 1257/0.

---

## Phase 5B — Production contract fixes `[liveview][ecto]`

- [x] **W1 — translate the 404 into the documented contract** — **done:** 404 → `:not_found`; other statuses pass through `lib/brando/cdn/client.ex`
      **Decision (user, triage):** translate in the impl; keep `client.ex:44`'s
      documented `{:error, :not_found}`.

      ```elixir
      @impl true
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

      Makes `uploads.ex:282`'s branch reachable and the operator message
      ("Uploaded object not found in bucket") actually fire.

- [x] **W1-doc — reconcile the moduledoc** — **done:** states why the contract boundary earns the logic; notes the 403 limit `lib/brando/cdn/client.ex`
      `Client.ExAws`'s moduledoc says *"Thin on purpose: anything with logic in it
      would be logic no test exercises."* W1 adds exactly that logic. Either state
      why this one translation earns its place (it is the contract boundary, and
      the mock cannot emit ExAws's shape) or the moduledoc now contradicts the
      code — the same class of defect W1 fixes.

- [x] **W1-verify — mutation-verify** — **done:** 3 tests against the real ExAws pipeline via a stub http_client; the old `:not_found` test stayed GREEN, as the review said `[testing]`
      Revert the translation, confirm `direct_finalize_test.exs:130` goes **RED**,
      restore. It currently passes against the broken client, which is the entire
      defect. Consider adding a case asserting the real `{:http_error, 404, _}` →
      `:not_found` mapping directly, so the translation itself is covered rather
      than only its effect.

- [x] **W3 — stop `:req_options` outranking the auth header** — **done:** all three reversed; provider_client_test 5/0 `[liveview]`
      `lib/brando/videos/uploaders/mux.ex:575`, `bunny.ex:433`,
      `cloudflare.ex:283`. Reverse the merge so built values win:

      ```elixir
      request_opts = Keyword.merge(req_options(), request_opts)
      ```

      Fix all three together — Cloudflare is pre-existing but identical, and
      leaving one inconsistent is worse than the original state.
      Verify: `mix test test/brando/videos/provider_client_test.exs` — every test
      sets only `plug:` (`:52`), so nothing should break. If something does, the
      seam was load-bearing in a way the review missed; stop and record it.

- [x] **S — finish enforcing `uid`** — **done:** checked first: production leaves it nullable (`brando_103` + `brando_123` index only). Fixture NOT tightened; reasoning recorded in the migration `[ecto]`
      `validate_required(:uid)` shipped in Phase 4, but `content_blocks.uid` is
      still nullable (`test_migrations.exs:296`) and `reject_deleted` runs only in
      the save path, not validate. Decide whether `null: false` belongs in the
      fixture migration. **Check the shipped consumer migrations first** — Phase 4
      found fixture-drift twice by doing exactly that, and this is the same
      question. If shipped apps have `null: false`, this is drift; if not, adding
      it makes the fixture stricter than production, which is the opposite error.

- [x] **S — namespace the upload-manager form id** — **done:** `brando-upload-manager-queue-form`; CSS keys on the class, no selector depended on the id `[liveview]`
      `lib/brando_admin/live/upload_manager.ex:647` — `upload-manager-queue-form`
      is unprefixed in a library. Prefix it (`brando-upload-manager-queue-form`)
      and confirm no CSS/JS/e2e selector depends on the current value:
      `rg 'upload-manager-queue-form' assets/ e2e/ lib/`.

**Gate 5B:** full `mix test` 1257/0 (or higher with new cases); credo 284.

---

## Phase 5C — Make the assertions capable of failing `[testing]`

Depends on 5A: these are verified by watching them go RED, which needs a
trustworthy harness.

- [x] **W7a — `partial_block_save_test.exs:64-73`** — **done:** `block_errors/1` returns `:no_block_change` for a vanished block
      Conflates "no errors" with "the block change vanished" — the precise
      data-loss shape the file exists to catch. Assert the surviving sibling's
      *content* in the returned changeset, not merely the absence of errors.

- [x] **W7b — assertions that test Ecto, not Brando** — **done:** all three re-pointed at `Page.changeset/5` / a control row; none deleted
      `partial_block_save_test.exs:203`, `asset_orphan_test.exs:48,61` assert
      Ecto's own behaviour against test-invented changesets and cannot go red for
      any Brando change. Either re-point them at Brando's changeset functions or
      delete them and say so — a test that cannot fail is worse than no test,
      because it reads as coverage.

- [x] **W7-verify — apply the phase's own standard** — **done:** 3 mutations, each watched RED then restored `[testing]`
      Each rewritten assertion must be watched going RED against the defect it
      claims to cover. Per the Phase 4 scratchpad: *"Writing a better assertion
      and watching it go green proves nothing — it has to be watched going RED."*

**Gate 5C:** `mix test` green; each touched assertion demonstrated RED-then-green
in `scratchpad.md`.

---

## Phase 5D — Config, docs, and latent traps

- [x] **W4 — sweep the `put_env(key, nil)` pattern** — **done:** `Brando.Test.Support.put_test_env/2`; 8 sites, 3 duplicated local `restore_env` helpers removed `[testing]`
      `test/brando/uploads/direct_finalize_test.exs:59` still restores with
      `put_env(..., original)`. Latent only — masked by `config/test.exs:5`. Apply
      the correct form already used at `provider_client_test.exs:31,41-42`:

      ```elixir
      original = Application.fetch_env(:brando, Brando.Files)
      on_exit(fn ->
        case original do
          {:ok, value} -> Application.put_env(:brando, Brando.Files, value)
          :error -> Application.delete_env(:brando, Brando.Files)
        end
      end)
      ```

      Then sweep the pre-existing twins: `utils_test.exs:206`,
      `uploads_test.exs:364`, and `html_test.exs:1108` (no restore at all).
      Consider extracting this into a `Brando.LiveCase` / test-support helper —
      four sites is enough to justify one.

- [x] **W5 — correct the overclaiming comment** — **done:** names `head_object`/`delete_object` and why the bulk ops stay out `config/test.exs:7`
      **Decision (user, triage):** comment only; the boundary design stands.
      "Every runtime S3 call goes through `Brando.CDN.Client`" is false —
      `cdn.ex:311,354,362` still call `ExAws.request` directly. Reword to name
      what actually routes (`head_object`, `delete_object`) and why the bulk
      operations deliberately do not, per `client.ex:11-22`.

- [x] **W9 — document the reset requirement** — **done:** moduledoc names the unique_violation and the `--reset` fix
      **Decision (user, triage):** leave the index, document it.
      `priv/repo/migrations/20260806000001_unique_block_uid_in_test_schema.exs` —
      add a note that it assumes no pre-existing duplicate uids, so a future
      non-`--reset` run gets an explanation instead of a raw Postgres error.

- [x] **S — decide on `config`/`test` in the hex package** — **done:** dropped; verified deps compile in `:prod` so neither was ever reachable `mix.exs:75-86`
      Harmless today (never evaluated by consumers; all placeholders), but a
      standing invitation for a real key. Either drop them from `files:` or record
      why they stay.

**Gate 5D:** `mix format --check-formatted`; `mix test` unchanged.

---

## Phase 5E — E2E `[testing]`

Needs `cd e2e && source .envrc`, a server on `:4444`, and rebuilt consumer assets
(`cd e2e/assets/backend && pnpm build`) if JS changed. **The user runs these.**

- [x] **W8 — make `goOffline` explicit** — **done:** `conn.close(4000, …)` `e2e/e2e/playwright/utils.js:67`
      `socket.js:552` only arms reconnect when `closeCode !== 1000`, and
      `conn.close()` requests exactly 1000 — the helper works only because
      `setOffline` aborts the socket into 1006 first. Use `conn.close(4000, …)`
      so the behaviour is stated rather than inherited from ordering.

- [x] **W10 — close the multiuser-sync race** — **done:** B waits to SEE A's edit before saving `block-multiuser-sync.spec.js:103`
      B saves before waiting to receive A's ship. Add the event-driven wait;
      surviving `waitForTimeout` removal did not make it correct.

- [x] **5E-verify — run the named specs individually first** — **done:** 4/0, then 9/0, then full suite 107/0 — see the baseline correction below
      `./test_e2e.sh --reset tests/blocks/block-recovery.spec.js`, then
      `…/block-multiuser-sync.spec.js`, then the full suite. Baseline **108/0**.
      Per `AGENTS.md`: when troubleshooting, run only the failing spec.

- [x] **S — trace the suite stdout noise** — **done:** `error_translator.ex` inspected the whole `Forms.Form`; now names the form + its fields. Unit-suite output 579 → 89 lines `[testing]`
      A large `Brando.Blueprint.Forms` struct is inspected to stdout mid-run. Not
      from the Phase 4 diff. Find the `IO.inspect`/`dbg` and remove it.

**Gate 5E:** full e2e 108/0 (or higher), `--reset`, against rebuilt assets.

---

## Completeness check — all 15 triage items mapped

| # | Finding | Task |
|---|---|---|
| W1 | `:not_found` never produced | 5B W1, W1-doc, W1-verify |
| W2 | `trap_exit` leak + over-drain | 5A W2a, W2b, W2-verify |
| W3 | `req_options` outranks auth | 5B W3 |
| W4 | `put_env(nil)` sweep | 5D W4 |
| W5 | `config/test.exs:7` overclaims | 5D W5 |
| W6 | selects not modelled | 5A W6 |
| W7 | assertions that cannot go red | 5C W7a, W7b, W7-verify |
| W8 | `goOffline` accidental | 5E W8 |
| W9 | unique index no dedupe | 5D W9 |
| W10 | multiuser-sync race | 5E W10 |
| S1 | `uid` half-enforced | 5B |
| S2 | unprefixed form id | 5B |
| S3 | `recovery_target` not version-tied | 5A |
| S4 | `mix.exs` ships config/test | 5D |
| S5 | suite stdout noise | 5E |

Nothing skipped, nothing silently dropped.

---

## Risks

- **Is the plan actually complete?** All 15 triage items map to tasks above; the
  table is the proof. Pre-existing items explicitly excluded by triage
  (`form.ex:6287+`, `upload_manager.ex:492`, `asset_intent.ex`) stay excluded —
  except `cloudflare.ex:283`, pulled into W3 for consistency.
- **What could make W1's fix wrong?** It adds logic to a module documented as
  logic-free, and only the 404 is translated — a 403-on-missing-object (some S3
  providers mask 404 as 403 without `s3:ListBucket`) would still fall through.
  If the target is DigitalOcean Spaces (per the test config), verify which it
  returns before assuming 404 is the only case.
- **What could make W2's fix wrong?** Restoring `trap_exit` to `prior` is correct
  only if nothing between the flag set and restore relies on trapping. If a test
  calls `kill_live/1` twice, the second restore must not re-enable trapping the
  first disabled — capture/restore is nested-safe as written, but confirm.
- **What is still unverified?** Whether shipped consumer migrations have
  `null: false` on `content_blocks.uid` (S1 hinges on it), and whether any
  selector depends on the current upload-manager form id (S2). Both are
  check-first steps, not speculative fixes.
- **Ordering risk.** If 5A is skipped or deferred, every mutation-verification in
  5B and 5C is being read off an instrument known to under-report failures. 5A
  is not cosmetic sequencing.

---

## Notes

Decisions and dead-ends go in the existing `.claude/plans/form-audit/scratchpad.md`
under a `## Phase 5` heading — it already carries Phases 0–4 and the Phase 4
review's retractions, and that continuity is worth more than a fresh file.
