# Phase 7 — Close the Phase 6 review findings

**Source:** `.claude/plans/form-audit/reviews/phase-6-triage.md` (14 approved, 0 skipped, 0 deferred)
**Review:** `.claude/plans/form-audit/reviews/phase-6-review.md`
**Slug:** `form-audit` · **Depth:** standard · **Created:** 2026-08-06

Own file, following the Phase 5 / Phase 6 precedent — `plan.md`'s Phases 0–4 are
followed by shared `## Verification` / `## Sequencing` / `## Risks` sections, so
appending after those would break it.

No research agents spawned: the review findings are the research, and each was
verified at file:line during the review. What *was* re-checked while planning is
recorded below, because four findings turned out to be differently shaped than
the triage recorded them.

---

## Four corrections to the triage, found while planning

### 1. B1's proof is now cheap — the real child already exists

The triage says "mount a **real** nested `live_render` child". One is already
mounted on every admin page. `lib/brando_admin/components/layouts/live.html.heex:2-4`
renders three:

```heex
{live_render(@socket, BrandoAdmin.Chrome, id: "brando-chrome", sticky: true)}
{live_render(@socket, BrandoAdmin.UploadManager, id: "brando-upload-manager-lv", sticky: true)}
{live_render(@socket, BrandoAdmin.Nav, …)}
```

So `live_form(conn, "/admin/pages/update/#{id}")` followed by
`find_live_child(view, "brando-chrome")` gives a real child of a real proxy with
no new fixture. B1-prove is roughly ten lines.

### 2. The reading, re-done independently, says the proxy dies — which is why B1-prove still has to run

Re-verified against **`phoenix_live_view 1.2.8`** (`mix.lock:87`), all in
`deps/phoenix_live_view/lib/phoenix_live_view/test/client_proxy.ex`:

- `put_view/3` calls `Process.monitor(pid)` (`:849`) and writes
  `pids: Map.put(state.pids, pid, new_view.topic)` (`:856`) — for *every* view,
  with no root/child distinction in the function.
- Children reach `put_view/3` at `:1001`, inside
  `recursive_detect_added_or_removed_children/4`.
- `handle_info({:DOWN, _ref, :process, pid, reason}, state)` (`:543-545`) resolves
  via `fetch_view_by_pid/2` → `state.pids` (`:909-912`) and returns
  `{:stop, reason, state}` on a hit.

This agrees with the review. **It changes nothing about the task**: this is the
third time in this audit a `file:line` reading has been proposed as a result, and
twice it was wrong. Reading it a second time is not the check. Running it is.

### 3. Nothing in the suite passes `:child` except the test of the `:child` branch

All five real call sites — `form_recovery_test.exs:36, 48, 151, 174, 198` — pass
`:root`. The only `:child` caller is `:75`, the harness test, against a stub. So
if B1-prove shows the proxy dies, collapsing to `kill_live/1` deletes one test
and rewrites five one-word call sites. The blast radius is small either way,
which is the argument for doing it properly rather than defending the split.

### 4. W-5's open question is already answered, in the direction that clears it

The triage asks whether `finalize_direct/3` bypasses a collision guard it should
be using. It does not — it uses a **stricter** one. `build_direct_filename/2`
(`uploads.ex:419-434`):

```elixir
# Mirror the server pipeline's filename processing … The server dedupes on
# filesystem collision; we can't cheaply check the bucket, so always uniquify
# unless the config overwrites.
true -> name |> maybe_slugify(cfg) |> Utils.unique_filename()
```

The direct path uniquifies **unconditionally**; `build_upload_key/2` uniquifies
only when `key_available?/2` says the key is taken. Unconditional is the
conservative side of that trade. There is no missing guard, so W-5 is not a live
upload defect and does not need its own phase. W-5-investigate reduces to
confirming the above and recording it; W-5-frame proceeds as written.

**New observation, not from the review** — flagged rather than silently actioned,
see 7C below: `build_upload_key/2` calls `key_available?/2` unconditionally, so a
config with `overwrite: true` + `force_filename` gets its forced name from
`get_valid_filename/2` (`utils.ex:1196-1199`) and then a `unique_filename/1`
suffix on top when the key exists — defeating the `overwrite` it just honoured.
Downstream-consumer surface only, same as the rest of W-5.

---

## Phase 7A — Harness: prove the premise, then act on it `[testing]`

Sequenced first for the Phase 5 and 6 reason: W-3, W-4, S-1, S-2, S-3 all touch
the two files B1 rewrites, and every later phase's RED run is read off this
harness.

- [x] **B1-prove — observe what a child kill does to the root proxy** — **the proxy dies.** Real sticky `brando-chrome` child via `find_live_child/2`; root proxy delivers `:DOWN` inside the same 500ms window `await_proxy_exit/1` allows. Causation established with a control test (mount, find child, kill nothing → proxy survives 500ms; also `child.pid != view.pid`), deleted after it did its job.
      New test in `form_recovery_test.exs`'s harness `describe` block. Mount a
      real admin form, `find_live_child(view, "brando-chrome")`, `Process.exit(child.pid, :kill)`,
      then assert on **proxy liveness** — `Process.alive?(proxy_pid)` where
      `{_ref, _topic, proxy_pid} = view.proxy` — not on elapsed time. Elapsed time
      is what the false premise predicts, which is why the existing `:child` test
      at `:72-77` cannot see this.
      Trap exits around it (the test process is linked to the root proxy) and
      restore the flag.
      If `find_live_child/2` on a **sticky** child misbehaves, fall back to a
      plain non-sticky `live_render` in a `test/support` LiveView rather than
      abandoning the real-child requirement — a stub proxy will not do here.
      Record the observed result in the scratchpad before writing B1-fix.

- [x] **B1-fix — follow what B1-prove showed** — took the **proxy dies** branch. `kill_live/1`: role argument, `:child` branch, `:root`/`:child` prose and the `:child` test all deleted; the proxy is now awaited unconditionally. Rationale restated in the `@doc`: the flunk was the fix, the role inference was not the defect.
      - **Proxy dies** (what the reading predicts) → the role distinction is not
        real. Collapse to `kill_live/1` that always awaits `await_proxy_exit/1`
        and flunks on timeout. Delete the `role` argument, the `:child` branch,
        the `:root`/`:child` prose at `live_case.ex:93-103`, and the `:child`
        test at `form_recovery_test.exs:69-79`. Restate W1's rationale in this
        plan and in the harness doc: **the flunk was the fix; the role inference
        was not the defect.** Keep B1-prove as the test that pins it.
      - **Proxy survives** → the doc is right, B1 is withdrawn. Say so
        explicitly in the plan, keep the two-role signature, and land S-2's
        version pin next to the citation so the claim stays checkable.

- [x] **B1-callsites — re-verify all five** — each re-read individually; all five take their `view` from `live_form/2` in their own test, i.e. root mounts. All now `kill_live(view)`.
      `form_recovery_test.exs:36, 48, 151, 174, 198`. Each is a root mount from
      `live_form/2`; confirm that individually, then apply whatever B1-fix
      decided.

- [x] **W-3 — replace the assertion that cannot fail** — `assert Process.alive?(proxy)`. RED-verified: stub proxy set to die at 100ms (before the 500ms flunk) → RED at the new line. A first mutation at 600ms did *not* go red, correctly — the proxy really was still alive when the flunk fired.
      `form_recovery_test.exs:65`: `refute_received {:EXIT, ^proxy, _}` →
      `assert Process.alive?(proxy)`. The stub proxy is `spawn/1` (`:292`) —
      unlinked, never dies — and `kill_live` only ever `receive`s, so nothing can
      put that message in the mailbox. Vacuous, inside the suite whose standard is
      that every assertion be watched go RED.

- [x] **S-1 — `try/after` around `kill_live`'s body** — flag restored from `after`. RED-verified by replacing the `after` body with `:noop`: both the happy-path and the flunk-path trap_exit assertions went RED.
      `live_case.ex:105-131`. Restore `prior_trap?` in the `after`, so the flag is
      handed back on the flunk path too, not only at `:129`. This is what
      dissolves W-4.

- [x] **W-4 — delete `restore_trap_exit/0` and its claim** — helper, call and comment gone. Replaced at the call site by `assert Process.info(self(), :trap_exit) == {:trap_exit, false}`, which pins S-1 instead of compensating for its absence.
      `form_recovery_test.exs:66` (call), `:299-302` (definition + comment). It
      sits under the only line it could protect, is skipped if that line raises,
      and ExUnit discards the flag on test-process exit anyway. Delete the helper
      **and** the comment claiming it compensates for a flunk-before-restore —
      after S-1 there is no such path. Do not relocate it.

- [x] **S-2 — pin `phoenix_live_view 1.2.8` next to both `client_proxy.ex:542-545`
      citations** — the pin landed and is correct. **The re-verification recorded here did not: it was wrong on three of five citations, and one of the three it broke itself.** Corrected by Phase 8's B1-fix, and left standing as the evidence for it. What this line originally claimed — "`put_view/3` monitors at `:848`, registers `state.pids` at `:856`, children reach it at `:1001`, `fetch_view_by_pid/2` at `:908-912`; the plan said `:849`, the monitor is on `:848`" — measures against the vendored 1.2.8 as: `:848` builds the struct and `Process.monitor(pid)` is `:849` (**the plan was right and S-2 changed it to a wrong line, then filed the change as a correction**); `:856` writes `state.views`, not `state.pids`, which is `:857`; `fetch_view_by_pid/2` is `:909-913` and `:908` is blank. Only `:1001` and `:542-545` held. That a verification pass *introduced* the defect it was verifying against — rather than merely failing to catch it — is the finding, not the off-by-one. (`live_case.ex:99, 141`), as the `view.ts` mirror elsewhere in
      this suite already does. B1 is the argument for this: a citation to a
      moving dep that said the opposite of what it was cited for. Applies in
      **both** B1-fix branches — a surviving citation needs the pin most.

- [x] **S-3 — retire the change-narration comments** — all four sites. State what the code does, not what it used to do:
      - `test/brando/plugs/lockdown_test.exs:2-7` — keep the `async: false`
        reason, drop "Phase 5 gave the restore a correct implementation…".
      - `test/support/live_case.ex:136-144` — rewritten by B1-fix anyway; land
        the result without the "this used to return `:ok` whenever…" history.
      - `mix.exs:75-88` — the `files:` rationale block; keep what the list
        excludes and why it is safe, drop "So they were shipped and never
        evaluated".
      - `test/brando_admin/live/form_recovery_test.exs:52-58` — rewritten by
        B1-fix/W-3; same treatment.
      Sequence **last in 7A**, after B1 and W-3/W-4 have rewritten two of the
      four sites.

---

## Phase 7B — `req_options` precedence: narrow the claim, widen the coverage

- [x] **W-1 — rewrite `ReqOptions.merge/2`'s `@doc`** — three sections: what it defends (the keys `built_opts` names), what reaches past it (`:auth`/`:plug`/`:adapter`/`:params`, with `:base_url` explained as safe), and `nil`-is-not-absent. Req line numbers re-verified against the vendored **req 0.7.2**: `steps.ex:236, 240, 244` and `:123` are all exact.
      `lib/brando/videos/uploaders/req_options.ex:15-28`. **No behaviour change** —
      the `Keyword.take/2` allowlist was offered and declined: it is a
      library-visible behaviour change and the actor is the config author, who
      already owns `runtime.exs`. The defect is the claim.
      State what the merge actually defends — **the keys the built options
      name** — and name the keys that reach past it, because Req's `auth` step
      uses `Req.Request.put_header/3`, not `put_new_header`
      (`deps/req/lib/req/steps.ex:236, 240, 244`): `req_options: [auth: {:bearer, …}]`
      survives the merge and then overwrites the built credential. Same route for
      `:plug`, `:adapter`, `:params`. `:base_url` is safe — it no-ops on absolute
      URLs (`steps.ex:122`).
      Keep "a config seam that can unset credentials is a config seam that will":
      it is still the argument for the merge *order*, just not for a total
      guarantee.

- [x] **W-2a — direct unit test of `ReqOptions.merge/2`** — new `test/brando/videos/uploaders/req_options_test.exs`, 5 tests. RED-verified by flipping the `Keyword.merge/2` argument order. Includes a test pinning the doc's reachable-keys claim, so that prose is falsifiable.
      Pure, no stub, free. Cover: built value wins on a colliding key;
      configured-only keys pass through; `nil` config reads as absent
      (`Application.put_env(key, nil)` is not the same as unset). Pin the
      documented-as-reachable keys too, so W-1's doc is falsifiable rather than
      just careful prose.

- [x] **W-2b — Bunny *and* Cloudflare mirrors** — Cloudflare took the mirror cleanly (`authorization: Bearer`), so all 3 call sites are now covered. RED-verified by re-inlining the merge in `bunny.ex:431` and `cloudflare.ex:282`: both went RED (`hijacked` reached the stub), then reverted.
      `test/brando/videos/provider_client_test.exs:174-196` pins precedence at
      1 of 3 call sites. Add the Bunny equivalent — assert the `AccessKey`
      header the provider built survives a hijacking `headers:` entry in
      `req_options` — so a re-inlined merge at `bunny.ex:431` goes RED. Today it
      stays green: those tests install their stub via `plug:` (`:52`,
      `cloudflare_test.exs:17`), which collides with nothing the providers build
      — the exact order-insensitivity the Mux test escaped.
      Cloudflare (`cloudflare.ex:281-285`) is the third site; add it in the same
      shape if its Bearer header takes the mirror cleanly.
      **Verify by re-inlining**: flip the merge order at `bunny.ex:431`, watch the
      new test go RED, revert. Same for Cloudflare if covered.

---

## Phase 7C — `build_upload_key/2`: confirm, then reframe `[elixir]`

Removal was offered and **declined for now** — it would undo most of 6B.

- [x] **W-5-investigate — confirmed, conclusion holds, wording corrected** — `build_direct_filename/2` does **not** uniquify "unconditionally"; it has three branches and the plan described only the third. Compared branch-by-branch against `build_upload_key/2` in the scratchpad: direct is stricter in the default branch, identical under `random_filename:`, and deliberately does not uniquify under `overwrite:`. `random_string/1` verified time-varying (`utils.ex:182`), not filename-deterministic. `finalize_direct/3`'s `head_object/2` runs *after* the client PUT, so collision detection there is impossible, not merely absent — it is verification. **Not a live upload defect; no escalation.**
      Correction 4 above holds that `build_direct_filename/2`
      (`uploads.ex:419-434`) uniquifies unconditionally, which is stricter than
      `build_upload_key/2`'s conditional uniquify, so `finalize_direct/3`'s bare
      `Brando.CDN.head_object/2` calls at `uploads.ex:266` and `:292` are
      verification of a completed upload, not a missing collision check.
      Confirm that reading against the `random_filename:` and `overwrite:`
      branches, then record the conclusion. **If it does not hold**, stop and say
      so — W-5 becomes a live upload defect and gets its own phase rather than
      being absorbed here.

- [x] **W-5-frame — corrected in both places** — `test/brando/utils_test.exs:515` and `phase-6-plan.md:196`. Both now say the upload path is a downstream consumer's, and that the absence of an in-repo caller is *why* a unit test is the only test there can be.
      The Phase 6 plan's "this is a production upload path, so the standard
      applies at full strength" and the matching test comment both describe a
      **downstream consumer**, not this tree — `build_upload_key/2`
      (`utils.ex:1174`) has no caller in this repo. Say downstream, in both
      places. Keep the test.

- [x] **New observation — written up, then FIXED on the user's call** — it is broader than the plan recorded: `build_upload_key/2` never honours `overwrite:` **at all**, with or without `force_filename`, because there is no `overwrite` branch on its `key_available?` test. `upload.ex:321-327` (local filesystem) and `build_direct_filename/2` (direct) both get it right, so this is the odd one of three, against a documented option (`file_config.ex:22`). See scratchpad. **User chose to fix now**: `build_upload_key/2` now short-circuits on `overwrite` and does not consult the bucket at all in that case. RED-verified by removing the branch — both new tests failed with `Mox.UnexpectedCallError`, i.e. the bucket *was* consulted, which is the defect itself. CHANGELOG entry under Fixes.
      `build_upload_key/2` calls `key_available?/2` unconditionally, so
      `overwrite: true` + `force_filename` (honoured at `utils.ex:1196-1199`)
      still collects a `unique_filename/1` suffix when the key exists. Not in the
      review; downstream-only. Write it up in the scratchpad and **ask** before
      touching it — this phase's remit is claims, not behaviour.

---

## Phase 7D — CDN surface and CHANGELOG `[elixir]`

- [x] **W-6 — CHANGELOG entry** — new `#### Breaking` section in Unreleased. Names the inversion with a before/after snippet, and also records the *error-semantics* change (old: anything but a clean hit read as absent; new: only `{:error, :not_found}` frees the key).
      `CHANGELOG.md`, Unreleased section. Name the replacement and its **inverted
      sense**: `key_available?/2` returns `true` when the key is *free*, where
      `key_exists?/2` returned `true` when it was *taken*. A consumer that
      swaps the name without inverting the branch overwrites live objects.
      Consumer-visible on a library, and the Unreleased section already carries
      prose for smaller changes.

- [x] **S-4 — documented** — and the raise site was probed rather than assumed: with `Brando.Images`' `:s3` unset it raises inside `get_s3_config/2` (`Map.from_struct(nil)`), not at `cdn_config.bucket` (`:411`) as the plan predicted. The `@doc` names both, since which one fires depends on config.
      `lib/brando/cdn/cdn.ex:381-396`. The `@doc` enumerates every other outcome
      — hit, uninterpretable error, a provider that does not 404 — but not this
      one: a `nil` `:cdn` raises on `cdn_config.bucket` (`:411`) before any
      presign or write. One sentence.

- [x] **S-5 — declined, with the reason in the CHANGELOG** as the task directed. `not key_available?(k, cfg)` is *not* the old function: on an uninterpretable error it returns `true` where `key_exists?/2` returned `false`. A shim would read as a compatibility layer while silently changing behaviour on exactly the path this work was about.
      Pairs with W-6. If taken, `@deprecated` + `def key_exists?(k, cfg), do: not key_available?(k, cfg)`
      — the inversion is the whole risk, and a shim that gets it right for the
      consumer is worth more than the CHANGELOG line alone. If declined, say why
      in the CHANGELOG entry so the next reader does not re-open it.

---

## Phase 7E — Pre-existing, carried in by the review

- [x] **S-6 — fixed at `cdn.ex:119`, the only warning site** (both occurrences; `:97, 107, 210, 348` never fire). Exact text: `Map.from_struct/1 with a module is deprecated, please pass a struct instead`. Cause: `config(Brando.Images, :s3)` returns `nil`, and `nil` is an atom, so it took the deprecated module clause and then died on `nil.__struct__/0`. Now guarded with a config error naming what is missing. **Output fell 78 → 45 lines (stderr 33 → 0)**, not the predicted −2 — each warning carried a ~16-line stacktrace.
      `get_s3_config(_, as: type)`. Warns on Elixir 1.20.0-rc.3 via **stderr** —
      it is two of the 76 baseline lines — and will harden into an error.
      Capture the exact warning text first (it is not in the review), fix the
      call, and confirm the baseline drops by two on stdout+stderr combined.
      Note `Map.from_struct/1` appears five times in this file (`:97, 107, 119,
      210, 348`); fix only the sites that actually warn, and say which.

- [x] **S-7 — confirmed live, and fixed.** `mix hex.build` listed **10_976 of 11_194** `assets/` entries as `node_modules/` (120 MB). `assets/` is now enumerated by subpath; assets entries 11_194 → 216, tarball 1.5 MB, 0 `node_modules`. **User chose to drop `assets/` entirely**: generator templates live in `priv/templates/`, and the admin frontend is distributed via Yalc. Final tarball **1388 files / 1.3 MB, 0 `assets/` entries**. `UPGRADE.md:796` turned out to sit in the historical *0.44.0* section, so the step was left intact with a dated note that the path no longer exists, rather than rewriting what 0.44.0 required. **Also found: `mix hex.build` could not complete at all** (`Missing metadata fields: links`), so the package was unpublishable; added `links:` using the URL already in the docs config.
      `mix.exs:89-98` lists `"assets"` as a whole directory. **This is very
      likely live**: `assets/node_modules/` exists locally at **120 MB**, is
      gitignored (`.gitignore:10`), and Hex does not read `.gitignore` — it globs
      the filesystem. Run `mix hex.build` and read the file list.
      If confirmed, narrow it. `assets/` holds `src/`, `css/`, `package.json`,
      `pnpm-lock.yaml`, the vite/postcss/europa configs, and `node_modules/`.
      Brando's frontend assets reach consuming apps through **Yalc**, not the Hex
      tarball, so decide what the tarball needs at all — the narrowest correct
      list beats an `exclude_patterns` bolt-on. Whatever is chosen, leave the
      reason in the comment (per S-3's standard: what it excludes and why that is
      safe, not what it used to be).

---

## Verification

Every phase ends with the full gate. Baselines are Phase 6's, **measured by that
review's verification runner, not inherited** — Phase 7 must hold them:

**Measured result (2026-08-06):** all gates green. `mix test` **1280 + 135
doctests / 0**, credo **284**, compile + format clean, unit-suite output **45
lines with 0 on stderr**, E2E **107 / 0** on a full `--reset` (8.9m) — the first
time this phase's E2E baseline has been measured rather than carried.

Two baselines moved and the new numbers are what Phase 8 should hold:
- **Output lines: 45, of which 29 are non-dot.** Use the non-dot figure. The
  total includes ~1413 progress dots whose line-wrapping shifts with the test
  count, so it moves without any output changing. S-6 removed 33 stderr lines,
  not the 2 the plan predicted.
- **Tests: 1280 + 135.** +9 net (+5 ReqOptions, +2 provider mirrors, +2
  `overwrite`, +1 B1-prove, −1 deleted `:child` test).

| Gate | Baseline | Phase 7 expectation |
|---|---|---|
| `mix test` | 1271 tests + 135 doctests, 0 failures | ≥ baseline, 0 failures (7A may net −1 test if B1-fix collapses the roles; 7B adds 2–3) |
| `mix credo --strict` | 284 | ≤ 284 |
| `mix compile --warnings-as-errors` | clean | clean |
| `mix format --check-formatted` | clean | clean |
| Unit-suite output | **76 lines on stdout+stderr combined** (43 on stdout alone) | ≤ 76; **74 after S-6** |
| E2E | 107 / 0 — **unverified last round**, carried from the implementer | run it this round; nothing here touches E2E surface, so a regression means something unplanned moved |

**Per-task RED requirement.** This audit's standard is that every new assertion
is watched go RED. Explicitly:
- B1-prove: state the observed outcome — it is the deliverable, not the test.
- W-2b: re-inline the merge at `bunny.ex:431` (and `cloudflare.ex:282` if
  covered), watch RED, revert.
- W-3: temporarily make the stub proxy die, watch `assert Process.alive?` go RED.
- W-2a: flip the `Keyword.merge/2` argument order, watch RED, revert.

Doc-only tasks (W-1, W-5-frame, W-6, S-2, S-3, S-4) have no RED. That is the
correct answer for them, and worth saying rather than manufacturing a test.

---

## Sequencing

```
7A  Harness            B1-prove → B1-fix → B1-callsites → W-3 → S-1 → W-4 → S-2 → S-3
      ↓ (harness signature is what every later RED run is read off)
7B  Precedence         W-1 ∥ W-2a → W-2b          ┐
7C  Upload guard       W-5-investigate → W-5-frame ├─ independent of each other
7D  CDN + CHANGELOG    W-6 → S-5 → S-4            ┘
      ↓
7E  Pre-existing       S-6 → S-7   (S-6 shifts the output baseline; do it before the final measure)
```

**7A first**, for the Phase 5 and 6 reason: it rewrites the instrument. B1-fix
also decides whether `live_case.ex:136-144` and `form_recovery_test.exs:52-58`
still exist, which is why S-3 sits at the end of 7A rather than in a sweep.

**7B, 7C, 7D are mutually independent** and can go in any order or in parallel.

**7E last**: S-6 moves the output-line baseline, so measuring it before S-6 lands
gives a number Phase 8 cannot reproduce.

---

## Risks

**What could make B1-prove inconclusive?** A sticky child behaving unlike a
plain one under `find_live_child/2`. Mitigation is in the task: fall back to a
non-sticky `live_render` in `test/support`. What is *not* acceptable is falling
back to a stub — that reproduces exactly the blindness B1 is about.

**What is this plan assuming that it has not checked?** That the E2E baseline of
107/0 still holds; the triage marks it unverified. Nothing in Phase 7 touches
E2E surface, so it is carried rather than re-derived — but it is carried
*knowingly*, and 7's verification runs it.

**Where could this phase quietly grow?** Two places, both fenced: W-5 becoming a
live upload defect (7C stops and escalates rather than absorbing it), and S-7's
narrowing of `files:` turning into a decision about what the Hex package is for.
If S-7 cannot be settled without that decision, ship the confirmed audit and ask.

---

## Traceability — every triage item has a task

| Triage item | Task(s) | Phase |
|---|---|---|
| B1 (BLOCKER) | B1-prove, B1-fix, B1-callsites | 7A |
| W-1 | W-1 | 7B |
| W-2 | W-2a, W-2b | 7B |
| W-3 | W-3 | 7A |
| W-4 | W-4 | 7A |
| W-5 | W-5-investigate, W-5-frame | 7C |
| W-6 | W-6 | 7D |
| S-1 | S-1 | 7A |
| S-2 | S-2 | 7A |
| S-3 | S-3 | 7A |
| S-4 | S-4 | 7D |
| S-5 | S-5 | 7D |
| S-6 | S-6 | 7E |
| S-7 | S-7 | 7E |

Skipped: none. Deferred: none.

**Carried forward, not triaged — third recording, so it is not lost a fourth
time:** the three video uploaders disagree on missing credentials. Mux and Bunny
**raise**; Cloudflare returns `{:error, :not_configured}` (`cloudflare.ex:272-273`).
A caller cannot handle both with one branch. Pre-existing; no finding has asked
for it; out of scope for Phase 7.
