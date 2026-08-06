# Test Review: Phase 4 — LiveView harness + 35 tests (`git diff HEAD~5`)

## Summary

The harness is real work and the two strongest files (`form_recovery_test.exs`'s
`recovery-critical DOM` block, `direct_finalize_test.exs`) are genuinely
mutation-sensitive. The problems are concentrated in three places: `kill_live/1`
leaves the test process trapping exits for the rest of the test, the
`put_env(key, nil)` restore bug is **still present in the file shipped in this
same phase**, and several of the 35 tests assert Ecto's behaviour rather than
Brando's and cannot go red for any regression in this repo.

Nothing here is release-blocking; two items are BLOCKER because they make later
tests silently non-failing, which is the failure mode this phase exists to
prevent.

---

## Iron Law Violations

| Law | Where | Note |
|---|---|---|
| 6 (no sleep) | `live_case.ex:164`, `utils.js:33,44` | Accepted: `:164` is a bounded poll on observable DOM; the two JS ones mirror app-side `setTimeout`s and are explicitly in-scope-exempt per the brief. |
| 7 (`verify_on_exit!`) | `provider_client_test.exs` | No `Req.Test.verify!`/`verify_on_exit!` — the Req stubs are never verified. See W4. Mox usage in `direct_finalize_test.exs:38` is correct. |
| 1 (async by default) | all five new `.exs` | Correct as `async: false` — all mutate `Application` env or use shared-sandbox LiveView. No violation. |

Mox: boundary-only (`Brando.CDN.Client`, `@callback head_object/3` at
`lib/brando/cdn/client.ex:45`), behaviour-backed, `expect` not `stub`,
`verify_on_exit!` present. This part is clean.

---

## Issues Found

### BLOCKER

- [ ] **`test/support/live_case.ex:101` — `trap_exit` is set and never restored.**
      ```elixir
      Process.flag(:trap_exit, true)
      Process.exit(pid, :kill)
      ```
      ExUnit gives each test a fresh process, so this does not bleed *across*
      tests — but it poisons the **remainder of the same test**, and every
      recovery test re-mounts after `kill_live/1`:

      - `form_recovery_test.exs:53`, `:76`, `:100` all call `live/2` again while
        trapping. `live/2` links the test process to the client proxy. If that
        second mount's proxy dies (mount raise, sandbox loss, async crash), the
        test process now receives `{:EXIT, ...}` **as a message instead of dying**.
        The test continues and can pass green on a LiveView that never mounted.
      - `flush_exits/0` (`:114-120`) then discards *every* `{:EXIT, _, _}` in the
        mailbox indiscriminately — not just the proxy's — and burns a 50 ms
        timeout doing it.

      Fix shape: capture and restore, and drain only the proxy's exit:
      ```elixir
      old = Process.flag(:trap_exit, true)
      ...
      receive do {:EXIT, ^proxy, _} -> :ok after 0 -> :ok end
      Process.flag(:trap_exit, old)
      ```

- [ ] **`test/brando/uploads/direct_finalize_test.exs:41` + `:59` — the
      `put_env(key, nil)` bug the phase fixed is still here, in a file shipped by
      the same phase.**
      ```elixir
      original = Application.get_env(:brando, Brando.Files)
      ...
      on_exit(fn -> Application.put_env(:brando, Brando.Files, original) end)
      ```
      This is the exact anti-pattern `provider_client_test.exs:39-44` documents
      as having "cost one cross-file flake to find" — and it is not applied here.
      It does not bite **today** only because `config/test.exs:5` sets
      `config :brando, Brando.Files, cdn: [enabled: false]`, so `original` is
      never `nil`. Delete or move that one config line and every subsequent test
      reading `Application.get_env(:brando, Brando.Files, [])` gets `nil` past the
      default. Use the `fetch_env`/`:error → delete_env` form from
      `provider_client_test.exs:31,42`.

      Answering the brief's question directly — **the fix is not complete**.
      Remaining instances of the same pattern (all pre-existing except the first):

      - `test/brando/uploads/direct_finalize_test.exs:59` — NEW, above.
      - `test/brando/utils_test.exs:206` — `put_env(..., org_cfg)` with no nil branch.
      - `test/brando/html_test.exs:1108` — `put_env` with **no restore at all**.
      - `test/brando/uploads_test.exs:364` — `on_exit(delete_env)` unconditionally,
        regardless of what was there before.

      Verified *correct* (no action): `input_test.exs:128`,
      `meta_drawer_test.exs:48`, `ai_test.exs:107`, `videos/upload_test.exs:265`,
      `uploaders/bunny_test.exs:14`, `uploaders/cloudflare_test.exs:22`,
      `uploads_test.exs:106`, `input/options_test.exs:40`.

### WARNING

- [ ] **W1 — `live_case.ex:55` — "must not be `async: true`" is documented, not
      enforced.** The moduledoc (`:21-24`) says the whole design depends on
      `shared: not async`, and `setup_sandbox/1` honours the tag. Nothing raises
      if someone writes `use Brando.LiveCase, async: true`; the LiveView process
      simply gets no sandbox connection and the mount fails with an ownership
      error that reads like an app bug. The file also never calls
      `Sandbox.allow/3` — isolation rests entirely on the unenforced convention.
      One line fixes it:
      ```elixir
      if tags[:async], do: raise("Brando.LiveCase cannot be async: true")
      ```

- [ ] **W2 — `live_case.ex:253-273` `recovery_target/1` re-implements LiveView
      client code, pinned by comment to `view.ts:2434-2450`.** The test is only as
      true as the mirror. A `phoenix_live_view` bump that changes
      `pushFormRecovery`'s element selection leaves
      `form_recovery_test.exs:88` passing green against a model of a client that
      no longer exists — and that test is the one carrying the `_target`
      regression. There is no assertion tying the mirror to the installed
      version. Minimum: a comment is not enough; consider a lock on the LV
      version or an e2e cross-check that the real client sends
      `_target=image_editor_upload`.

- [ ] **W3 — `partial_block_save_test.exs:64-73` — `block_errors/1` conflates
      "no errors" with "the block change vanished".**
      ```elixir
      case Changeset.get_change(entry_block, :block) do
        nil -> []
        block_cs -> Keyword.keys(block_cs.errors)
      end
      ```
      So `assert block_errors(changeset) == [[], [:type], []]` (`:114`) passes
      both when the siblings are intact-and-clean *and* when their `:block`
      changes were dropped entirely — which is precisely the silent data-loss
      shape the file's own header says it exists to catch. `:236-242` and
      `:247-253` inherit the same blind spot. Return a distinct sentinel
      (`nil -> :no_block_change`) so the two are not the same value.
      (The `:121` sibling-content test does cover the gap for one case, so this
      is a weakened assertion, not an uncovered one.)

- [ ] **W4 — `provider_client_test.exs:49-53` — `Req.Test` stubs are never
      verified, and the seam is silently optional.**
      ```elixir
      Req.Test.stub(stub_name, fun)
      with_config(module, Keyword.put(config, :req_options, plug: {Req.Test, stub_name}))
      ```
      Ownership mode is correct for these tests (stub is bound to the test
      process, `async: false`, the HTTP call happens in the test process). Two
      gaps:
      1. No `Req.Test.verify_on_exit!`. All the interesting assertions in the
         Mux/Bunny happy-path tests live *inside the plug function* (`:64-70`,
         `:132-138`). They only run if the plug runs. Today the trailing
         `assert {:ok, ...}` forces it, so there is no live bug — but the
         assertions are load-bearing and unguarded.
      2. If a refactor drops the `:req_options` config key, the stub is simply
         not installed and the client **hits the real network** instead of
         failing. `Req.Test.verify!/1` closes both.

- [ ] **W5 — `form_recovery_test.exs:109-116` — `Process.alive?` is the wrong
      assertion and the setup line is a no-op.**
      ```elixir
      params = Map.delete(form_params(html, "#page_form_form"), "_target")
      view |> element("#page_form_form") |> render_change(params)
      assert Process.alive?(view.pid)
      ```
      `form_params/2` never inserts `_target`, so the `Map.delete` deletes
      nothing — the intent reads as "strip it" but it is decorative, and would
      stay decorative if `form_params/2` later started adding one. And if the
      view *does* die, `render_change` raises before line 115 is reached, so the
      assertion never fires; conversely a crash landing a microsecond later makes
      `Process.alive?` a race. `assert render(view) =~ "page_form_form"` is the
      deterministic form (it round-trips through the live process).

- [ ] **W6 — `e2e/utils.js:65-69` — `goOffline`'s reconnect arming depends on an
      undefined close code.** The comment claims closing `conn` leaves
      "reconnection still armed". Verified against
      `e2e/deps/phoenix/assets/js/phoenix/socket.js:552`:
      ```js
      if(!this.closeWasClean && closeCode !== 1000){ this.reconnectTimer.scheduleTimeout() }
      ```
      `conn.close()` with no arguments requests close code **1000**. If Chromium
      completes the closing handshake (or synthesises 1000 while offline),
      `scheduleTimeout()` is never called, no reconnect is armed, and `goOnline`
      falls through to a 30 s `syncLV` timeout. It presumably works today only
      because `setOffline(true)` runs first and the aborted socket surfaces as
      1006 — i.e. by accident of ordering. Make it deterministic:
      `conn.close(4000, "test partition")`. Any non-1000 code guarantees the
      branch.
      Secondary: `expect(page.locator('.phx-connected').first()).toBeHidden()`
      (`:68`) also passes when the selector matches **nothing at all**, so a
      wrong-page `goOffline` succeeds silently.

- [ ] **W7 — `block-multiuser-sync.spec.js:102-103` — a sleep became a
      sender-side poll and left the receiver race intact.**
      `editBlockOneAndBlur` ends at `awaitBlockShip(page)`, which settles **A**
      only (`utils.js:43-46`: sleep + `syncLV` on the sender). `saveAsBAndVerify`
      then immediately clicks Save on **B**, with no wait for B to have applied
      the shipped op. The op reaches B over B's own socket asynchronously, so
      this is the original flake with a shorter sleep in front of it. The third
      test (`:148-151`) does it right — assert on B first:
      ```js
      await expect(secondUserPage.locator('.header-block textarea').nth(0))
        .toHaveValue('Alpha edited by A', { timeout: 5000 })
      ```
      before saving. Same applies at `:123`.

- [ ] **W8 — Tests that cannot go red for any Brando change.** These pass against
      arbitrary mutations of this repo's source; they assert Ecto's or the
      test's own behaviour:
      - `asset_orphan_test.exs:48-56` — an image with `deleted_at == nil` is
        trivially untouched by a 30-day purge. There is no branch under test.
      - `asset_orphan_test.exs:61-78` — the failed insert is a changeset the
        *test* hand-builds (`Changeset.validate_required([:uri])`); it never
        touches upload or form code, and no Brando code path could delete the
        image. This is the "accepted-by-design orphan" contract stated as prose,
        not pinned by execution.
      - `partial_block_save_test.exs:203-226` — same shape: the test invents
        `validate_required([:uri])` and then asserts `put_assoc` changes survive
        an invalid parent. That is Ecto's guarantee, not Brando's.
      The moduledocs justify *why these contracts matter*; the objection is that
      the assertions do not exercise the code that would break them. Counting
      them toward "35 tests of coverage" overstates the delta. The genuinely
      mutation-sensitive members of these files are
      `asset_orphan_test.exs:136-149` (the FK-wedge regression — good), and
      `partial_block_save_test.exs:236`/`:247` (uid).

- [ ] **W9 — `partial_block_save_test.exs:37-58` — `save_roots/3` re-implements
      the production save pipeline rather than calling it.**
      ```elixir
      |> ContentBlocks.reject_deleted(true)
      |> ContentBlocks.strip_render_artifacts()
      |> Enum.map(&Brando.Utils.set_action/1)
      ```
      The header says it "drives the same save path `BlockField`'s
      `fetch_root_blocks` and the Form run" — but it drives a *copy* of it. If
      the real pipeline reorders those three stages (or gains a fourth), the
      tests keep passing on the old order. This is the classic mutation
      survivor: the bug lands in `form.ex`/`block_field.ex` and the test is
      unaffected. If any of that is reachable as a public function, call it.

### SUGGESTION

- [ ] `live_case.ex:131-139` — `live_form/3` waits `render_async(view, 5_000)`
      but then `await_selector` with its 2 s default (`:148`). On a loaded CI box
      the shorter deadline governs. Align them, or thread a timeout through.
- [ ] `live_case.ex:186` — `Floki.find(form_selector) |> Floki.find("input, ...")`
      only serializes descendants. A browser (and `form.elements`) also submits
      controls associated via `form="id"` outside the element. Fine for today's
      DOM; a footgun if the entry form ever hoists an input.
- [ ] `live_case.ex:219-227` — `selected_option/2` takes only the first
      `selected` option and ignores `<select multiple>`. Same for checkbox groups
      with `name="x[]"`. Not exercised yet.
- [ ] Duplicate case `use`: `provider_client_test.exs:23-24`,
      `partial_block_save_test.exs:11-12`, `asset_orphan_test.exs:25-26`,
      `direct_finalize_test.exs:19-20` all do `use ExUnit.Case, async: false`
      **and** `use Brando.ConnCase`. `ConnCase` is an `ExUnit.CaseTemplate` that
      already brings in `ExUnit.Case`; the first line is dead and its `async:`
      value is not the one in effect (ConnCase's default is). Both are `false`
      today so the behaviour is right by coincidence. Drop the bare `use`.
- [ ] `direct_finalize_test.exs:71-82` — `params/1` builds an **atom-keyed** map
      (`key:`, `resolved_target:`, `mime_type:`). A real `direct_complete`
      arrives from the client with **string** keys. Worth confirming
      `finalize_direct/3` is called with atoms at the real call site; if the
      channel hands it strings, this suite never exercises the shape that ships.
- [ ] `provider_client_test.exs` moduledoc names "Mux/Bunny/**Cloudflare**
      clients" but there are no Cloudflare tests (3 Mux + 2 Bunny = 5). Also no
      Bunny non-2xx case, though `:110` establishes the pattern for Mux. Obvious
      hole given the moduledoc's own framing.
- [ ] `form_recovery_test.exs:22-38` and `:45-55` are harness self-checks and a
      baseline characterization; neither can fail on a production regression.
      Keep them, but they are documentation, not coverage.
- [ ] `form_recovery_test.exs:96` — `assert captured["_target"] == ["image_editor_upload"]`
      will fail (correctly but confusingly) the moment any named non-hidden input
      is added above the image editor upload input in the form. The comment at
      `:94-95` anticipates this; a message on the assert would make the failure
      self-explaining.
- [ ] `asset_orphan_test.exs` calls `Query.clean_up_soft_deletions()` — a
      repo-global purge — in five tests. Safe under `async: false` + shared
      sandbox, dangerous the instant anyone flips the tag. Worth a comment
      alongside the `use`.
- [ ] Factories: usage is correct throughout (`Factory.build(:gallery_object, ...)`
      nested inside `Factory.insert(:gallery, ...)` at `asset_orphan_test.exs:177`
      is the right build-inside-insert shape). No hardcoded unique values found
      in the new files.

### Coverage holes across the 35

- `Brando.CDN.Client.delete_object/3` (`client.ex:49`) has a `@callback` and a
  Mox mock but no test in this phase; only `head_object` is driven.
- The drawer recovery form is asserted to *exist* (`form_recovery_test.exs:142`)
  and to carry `phx-change="noop"`, but nothing asserts that pushing `noop`
  is actually harmless — the reason it is unconditional.
- No Elixir-level counterpart to the e2e block-recovery gap. It is honestly
  documented in the spec, but there is no server-side test that would flip when
  the identity redesign lands.

---

## Pre-existing (one line each, not in scope)

- `test/brando/html_test.exs:1108` — `Application.put_env` with no restore.
- `test/brando/utils_test.exs:206` — restore via `put_env(..., original)`, no nil branch.
- `test/brando/uploads_test.exs:364` — unconditional `delete_env` on exit.
- `test/test_helper.exs:24` — `Supervisor.start_link/2` return unmatched and the supervisor unnamed.
