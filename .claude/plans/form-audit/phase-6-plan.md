# Phase 6 — Close the Phase 5 review findings

**Source:** `.claude/plans/form-audit/reviews/phase-5-triage.md` (8 approved, 0 skipped, 0 deferred)
**Review:** `.claude/plans/form-audit/reviews/phase-5-review.md`
**Slug:** `form-audit` · **Depth:** standard · **Created:** 2026-08-06

Kept in its own file, following the Phase 5 precedent — `plan.md` is a living
document whose Phases 0–4 are followed by shared `## Verification` /
`## Sequencing` / `## Risks` sections, and appending after those would break it.

No research agents spawned: the review findings are the research, and each was
verified at file:line during the review. What *was* re-checked while planning is
recorded below, because two findings turned out to be differently shaped than
the triage recorded them.

---

## Three corrections to the triage, found while planning

The triage file was written from agent findings. Reading the actual code to plan
the fixes changed three of them. Recording rather than silently adjusting:

### 1. W3's accepted consequence was wrong — in your favour

The triage says fail-closed means "a transiently-erroring bucket now blocks an
upload that used to proceed." **It does not.** `key_exists?/2` has exactly one
caller, `Brando.Utils.build_upload_key/2` (`utils.ex:1182`):

```elixir
if Brando.CDN.key_exists?(key, file_cfg) do
  unique_filename(key)   # collision → pick a new name
else
  key                    # free → use as-is
end
```

The `true` branch **renames**, it does not block. So failing closed means an
uninterpretable HEAD result produces a uniquely-named upload instead of an
overwrite. Nothing is blocked; the only cost is an occasional unnecessary
rename. This is strictly better than the trade you accepted.

### 2. W2 is a comment fix, not a code fix

Leaving unrelated `{:EXIT, …}` messages queued is **correct behaviour**, not a
leak. The bug Phase 5 fixed was the *opposite* — the old `flush_exits/0`
swallowed every exit for 50 ms, so a test carried on past a crash it never
observed. A selective receive that leaves other exits in the mailbox is exactly
right: they belong to the test, which should be able to observe them.

Only the comment is wrong ("drains only `view.proxy`'s pid" — accurate about
matching, not disposal). Fix the sentence, not the function.

### 3. S3 is narrower than reported

The agent said the header comment calls the sending-side helpers
"event-driven". It does not — `utils.js:41-45` explicitly disclaims the
receiving side and correctly reserves "event-driven" for the retrying `expect`
on the other page. The file's comments are better than the finding implied.

What *is* loose: `awaitBlockDebounce`'s "Replaces a flat `waitForTimeout(600)`"
(`utils.js:28`) reads as *removing* a sleep, when it renames one to a named
constant and adds a `syncLV`. Scope S3 to that sentence.

---

## Sequencing rationale

**6A first, for the same reason 5A went first.** W1 changes the signature of the
harness every other verification is read off. Doing it first means 6B and 6C are
verified on an instrument that can no longer convert a hung root proxy into a
pass — and the RED runs those phases require are only trustworthy after that.

6B (production) and 6C (refactor) are independent of each other. 6D is prose.

---

## Phase 6A — Make the harness state its assumption `[testing]`

- [x] **W1 — `kill_live/2` takes the proxy relationship from the caller**
      *Shipped as planned. `await_proxy_exit/1` now flunks on timeout and is
      only reached for `:root`.*
      `test/support/live_case.ex:95-142`

      **Decision (user, triage):** the caller declares it. No inference.

      The two roles want genuinely different behaviour, which is why the
      inference was never reducible to a better guess:

      | Role | Proxy behaviour | Correct wait |
      |---|---|---|
      | `:root` | killing the view stops the proxy (`client_proxy.ex:542-545`) | await the exit; **flunk** on timeout |
      | `:child` | shares the root's proxy, which stays alive | **nothing in flight — do not wait at all** |

      So `:child` skips the await entirely rather than waiting 500 ms and then
      deciding. That removes both the race *and* a pointless half-second.

      ```elixir
      def kill_live(view, role) when role in [:root, :child] do
        pid = view.pid
        {_ref, _topic, proxy_pid} = view.proxy
        ref = Process.monitor(pid)

        prior_trap? = Process.flag(:trap_exit, true)
        Process.exit(pid, :kill)

        receive do
          {:DOWN, ^ref, :process, ^pid, _reason} -> :ok
        after
          1_000 -> flunk("LiveView #{inspect(pid)} did not exit within 1s")
        end

        if role == :root, do: await_proxy_exit(proxy_pid)
        Process.flag(:trap_exit, prior_trap?)
        :ok
      end
      ```

      `await_proxy_exit/1` loses the `Process.alive?/1` escape hatch and flunks
      on timeout, like the `{:DOWN, …}` wait above it already does.

      **No default arg.** A default reintroduces exactly the implicitness this
      removes — a child view would silently take the root path again.

- [x] **W1-call-sites — update all five, explicitly `:root`**
      *Re-verified at each site rather than trusting the plan: all five views come
      from `live_form/3` → `Phoenix.LiveViewTest.live/2`, i.e. root mounts.*
      `form_recovery_test.exs:36,48,123,146,170`. All five kill root views.

- [x] **W1-verify — watch it go RED** `[testing]` — **both branches RED, kept as regression tests**
      *Two tests, not one. `:root` with a stubbed live proxy: old code `:ok`,
      new code flunks. `:child`: mutating `if role == :root` to unconditional
      made it flunk at 500ms. The `:child` branch had no coverage at all before.*
      Per the standard this audit has held since Phase 3, and the way 5A was
      verified. Simulate a root proxy that outlives its view (e.g. a stubbed
      `proxy_pid` pointing at a process that ignores the exit) and confirm
      `kill_live(view, :root)` now **flunks** where the old code returned `:ok`
      after 500 ms. Delete the throwaway, or keep it if it reads as a harness
      regression test — 5A kept its `trap_exit` one and that was the right call.

- [x] **W2 — correct the comment; leave the function** `test/support/live_case.ex:123-130`
      See correction 2 above. State that non-matching `{:EXIT, …}` messages stay
      in the mailbox **deliberately**, because swallowing them is the defect the
      old `flush_exits/0` had.

- [x] **S1 — "nested-safe" is the wrong word** `test/support/live_case.ex:106-107`
      `kill_live` calls are sequential, not nested; Elixir cannot re-enter a
      synchronous function on the same process. Say what is true: capture/restore
      composes across *repeated* calls.

**Gate 6A:** `mix test test/brando_admin/live/form_recovery_test.exs` green;
full `mix test` still 1265/0.

---

## Phase 6B — Stop the overwrite guard failing open `[security]`

- [x] **W3 — only a definitive `:not_found` frees the key**
      *Shipped as `key_available?/2`; `key_exists?/2` removed. Caller inverted.*
      `lib/brando/cdn/cdn.ex:381-383` · pre-existing, single caller

      **Decision (user, triage):** fail closed.

      ```elixir
      @doc """
      Whether `object_key` is free to write to.

      Only a definitive `{:error, :not_found}` frees the key. A hit, or an error
      we cannot interpret — a 403 from a bucket that masks 404 without
      `s3:ListBucket`, a timeout — reads as occupied, because the caller uses a
      `true` here to justify writing to that key. Guessing "free" overwrites a
      live asset's bytes under its existing row; guessing "taken" costs one
      unnecessary rename.
      """
      def key_available?(object_key, field_cfg) do
        head_object(object_key, field_cfg) == {:error, :not_found}
      end
      ```

      **Rename, don't re-point.** Keeping the name `key_exists?` while returning
      `true` for "unknown" makes the name lie — the same defect class this audit
      has been closing since Phase 4. `key_available?` is true exactly when
      writing is safe, so the caller reads straight:

      ```elixir
      if Brando.CDN.key_available?(key, file_cfg), do: key, else: unique_filename(key)
      ```

      **Public-API note:** `key_exists?/2` is public on `Brando.CDN` (a library),
      but has no `@doc`, one internal caller, and no reference in `guides/`,
      `CHANGELOG.md` or `priv/`. Removing it outright is low-risk. Flagging
      because it is a consumer-visible removal, not because it is likely to bite.

- [x] **W3-verify — the mutation has to be watched** `[testing]` — **RED confirmed**
      *Three cases in `utils_test.exs`. Reverting to the fail-open predicate
      returned the bare key on a 403, exactly as predicted.*
      This is a production upload path, so the standard applies at full strength.
      Drive `build_upload_key/2` with a `Client.Mock` returning
      `{:error, {:http_error, 403, _}}` and assert the key comes back **renamed**.
      Then revert `key_available?` to `match?({:ok, _}, …)` and confirm the test
      goes **RED** — it must, because the old code returns the bare key there.

      Add the `{:error, :not_found}` → not-renamed case too, so the happy path is
      covered by something other than its absence.

**Gate 6B:** full `mix test` (1265/0, plus the new cases); credo 284.

---

## Phase 6C — Give the merge precedence one owner `[elixir]`

- [x] **W4 — extract the precedence rule, not the whole skeleton**
      *New `Brando.Videos.Uploaders.ReqOptions.merge/2`; Mux and Bunny lose their
      private `req_options/0`, Cloudflare loses its inline read.*
      `lib/brando/videos/uploaders/{mux.ex:560-579, bunny.ex:418-437, cloudflare.ex:283-287}`

      The three `api_request/3` bodies are **not** the same function with
      cosmetic differences, and planning them as one extraction would be wrong:

      | | Mux | Bunny | Cloudflare |
      |---|---|---|---|
      | Auth | Basic (`base64(id:secret)`) | `AccessKey` header | `Bearer` |
      | URL | `@base_url <> path` | `@base_url <> path` | `"#{@api_base}/#{account_id}#{path}"` |
      | Missing creds | **raises** | **raises** | returns `{:error, :not_configured}` |
      | Arity | `/3` | `/3` | `/4` (`extra_headers`) |

      What *is* byte-identical, and what actually drifted, is the merge:

      ```elixir
      Keyword.merge(get_config(:req_options) || [], built_opts)
      ```

      Extract **that** — one shared helper owning the precedence rule and the
      comment explaining it — and leave auth, URL and body construction with
      each provider. A single-purpose helper the three call is enough to stop
      one of them drifting; collapsing `api_request/3` itself would be a much
      larger change that this finding does not justify.

- [x] **W4-verify** — **the extraction WAS untested; a new test now covers it.**
      *The four pre-existing tests all passed with the merge flipped — the stub
      arrives via `plug:`, which collides with nothing the providers build, so
      the merge is order-insensitive for them. Added a test that configures a
      colliding `headers:` entry; flipped, the stub sees `hijacked:hijacked`.
      Original line:* `mix test test/brando/videos/provider_client_test.exs`.
      Then mutate: revert one provider's call to the old argument order and
      confirm a test goes RED. If none does, the extraction is untested and the
      original W3 defect could recur unnoticed — say so rather than moving on.

**Gate 6C:** `mix test` green; credo 284 (an extracted helper should not move it).

---

## Phase 6D — Documentation truthfulness `[docs]`

No behaviour changes. Each is a claim that outruns what the code does — the
defect class this audit has been closing since Phase 0.

- [x] **S2 — narrow the `mix.exs` comment**
      *`priv/`'s placeholders re-verified before writing the replacement:
      `deployment.cfg:8` (`DB_PASS`), `.envrc.prod:3`, `fabfile.py`'s `SSH_PASS`.* `mix.exs:74-85`
      The "standing invitation for a real key to be added to a file nobody
      thinks of as published" argument applies verbatim to `priv/`, which still
      ships credential-shaped placeholders it *must* ship
      (`brando.install/deployment.cfg:8,13`, `fabfile.py:968`, `.envrc.prod:3`).
      Keep the part that is established and load-bearing — these two dirs were
      shipped, never evaluated, and dropping them also removes the test fixtures
      — and drop the general secrets argument `priv` contradicts.

- [x] **S3 — correct `awaitBlockDebounce`'s framing** `e2e/e2e/playwright/utils.js:28`
      See correction 3. "Replaces a flat `waitForTimeout(600)`" reads as removing
      a sleep; it renames one and adds a `syncLV`. Say that. Leave
      `awaitBlockShip`'s comment alone — it is already accurate.

- [x] **S4 — `lockdown_test.exs:2` → `async: false`** `[testing]`
      Mutates global `:brando, :lockdown` while `async: true`. Latent today
      (nothing else reads the key), which is why it was left in Phase 5 — but
      `put_test_env/2` made the *restore* correct without making the
      *concurrency* correct, and the next test that touches `:lockdown` inherits
      a flake that looks like a bug in itself.

**Gate 6D:** `mix format --check-formatted`; `mix test` unchanged.

---

## Completeness check — all 8 triaged items mapped

| # | Finding | Task | Note |
|---|---|---|---|
| W1 | harness launders timeout | 6A W1, W1-call-sites, W1-verify | |
| W2 | undrained EXITs | 6A W2 | **comment only** — see correction 2 |
| W3 | `key_exists?` fails open | 6B W3, W3-verify | consequence corrected — see correction 1 |
| W4 | uploader triplication | 6C W4, W4-verify | scoped to the merge, not `api_request` |
| S1 | "nested-safe" wrong word | 6A S1 | |
| S2 | `mix.exs` comment vs `priv` | 6D S2 | |
| S3 | "event-driven" overstates | 6D S3 | narrowed — see correction 3 |
| S4 | `lockdown_test` async | 6D S4 | |

Nothing skipped, nothing silently dropped.

---

## Baselines to hold

Measured by the Phase 5 review panel, not inherited from a plan:

| Gate | Baseline | Measured after Phase 6 |
|---|---|---|
| `mix test` | 1265 tests + 135 doctests, 0 failures | **1271 + 135, 0** (+6 new) |
| `mix credo --strict` | 284 | **284** |
| `mix compile --warnings-as-errors` | clean | clean |
| `mix format --check-formatted` | clean | clean |
| E2E (`./test_e2e.sh --reset`) | 107 passed / 0 failed | **107 / 0** (8.9m) |
| Unit-suite stdout | 76 lines | **76** |

The six new tests: 2 harness (`kill_live/2` root-flunks, child-skips), 3 upload
key (`:not_found` / hit / 403), 1 `:req_options` precedence.

Movement in any of these gets explained in `scratchpad.md`, not absorbed.

Only S3 touches `e2e/`, and it is a comment — so a full e2e run is not required
to prove 6D. Run it once at the end regardless, since 6A changes the harness the
Elixir suite depends on and `--reset` is cheap relative to being wrong.

---

## Risks

- **What could make W1 wrong?** If any current call site kills a *child* view
  while passing `:root`, it will now flunk where it previously passed. All five
  were checked and all are root mounts via `live_form/3` — but the check is the
  deliverable, so re-verify at each site rather than trusting this line.
- **What could make W3 wrong?** If any S3 provider returns something other than
  a 404 for a genuinely absent key, every upload to that backend gets renamed —
  functional, but the collision-avoidance suffix appears where it need not.
  `Client.ExAws` maps only 404 → `:not_found` (Phase 5B, deliberate), so this
  reduces to: does the configured provider 404 on absence? DigitalOcean Spaces
  does. Worth stating in the moduledoc rather than assuming for all providers.
- **What could make W4 wrong?** Nothing structural — but if the extracted helper
  is not covered by a test that fails when the argument order flips, the
  extraction has moved the defect rather than fixed it. That is what W4-verify
  is for, and a green run there is not sufficient; the RED is.
- **Is the plan complete?** All 8 triaged items map to tasks; the table is the
  proof. Three were re-shaped by reading the code, and each correction is
  recorded above rather than folded in silently.
- **Found while planning, deliberately out of scope:** the three uploaders
  disagree on missing-credential behaviour — Mux and Bunny **raise**, Cloudflare
  returns `{:error, :not_configured}`. A caller cannot handle both with one
  branch. Real, pre-existing, and not something this phase's findings asked for.
  Recorded so it is not lost.

---

## Notes

Decisions and dead-ends go in `.claude/plans/form-audit/scratchpad.md` under a
`## Phase 6` heading, continuing Phases 0–5 there.
