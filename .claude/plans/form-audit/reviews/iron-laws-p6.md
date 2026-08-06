# Iron Law Violations Report — Phase 6

## Summary
- Files scanned: 13 changed (`git diff HEAD~5`)
- Iron Laws checked: 26 of 26 (pattern sweep); relevant hits: #19 (comments),
  error-handling/fail-open, naming honesty
- Violations found: 6 (1 blocker, 0 warning, 5 suggestion)

No LiveView/Ecto/Oban/security-pattern law was tripped: the diff adds no mount,
no query, no worker, no `raw/1`, no `String.to_atom/1`, no `:float` field, and
`ReqOptions.merge/2` preserves the previous precedence exactly (verified: all
three providers' `get_config/1` read `Application.get_env(:brando, __MODULE__, [])
|> Keyword.get(key)`, so the extraction is byte-equivalent).

The three DELIBERATE DECISIONS listed in the brief were checked and are not
flagged.

---

## Critical Violations (BLOCKER)

### [naming/doc honesty] `kill_live/2`'s `:child` premise is contradicted by the code it cites
- **File**: `test/support/live_case.ex:102-103` (doc) and `:128` (the branch)
- **Code**:
  ```
  * `:child` — shares the root's proxy, which stays alive. Nothing is in
    flight, so nothing is awaited: no race, and no pointless half-second.
  ```
  ```elixir
  if role == :root, do: await_proxy_exit(proxy_pid)
  ```
- **Confidence**: LIKELY (code evidence is definitive; the residual doubt is
  only whether a caller's "child" is a real nested LiveView process)
- **Why it is wrong**: the `:root` bullet cites `client_proxy.ex:542-545`. Read
  that handler in the vendored dep:

  ```elixir
  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    case fetch_view_by_pid(state, pid) do
      {:ok, _view} -> {:stop, reason, state}
  ```

  `fetch_view_by_pid/2` looks up `state.pids`, and `put_view/3`
  (`client_proxy.ex:846-859`) inserts **every** view into `state.pids` and
  monitors it — including children, which reach `put_view/3` via
  `recursive_detect_added_or_removed_children/…` (`client_proxy.ex:997-1002`).
  So killing a *child* view also stops the shared proxy. The proxy does **not**
  stay alive, and an exit **is** in flight.

  Consequence, in order: `kill_live(view, :child)` skips the await, restores
  `trap_exit` to `false` at line 129, and the `{:EXIT, proxy, :killed}` signal
  from the process `live/2` linked the test to then arrives **untrapped** — it
  kills the test process. If it wins the race before the restore, it instead
  sits in the mailbox as a stray message the next `assert_receive`/`refute_received`
  can trip over. Either way the failure reads as a bug in the test, which is the
  exact defect class Phase 6A set out to remove.

  The `:child` branch has no real call site today (only the stubbed test below),
  so this is latent — but it is a documented invariant that is false, shipped as
  the justification for the branch.
- **Fix**: either await the proxy exit for both roles (with the `:root` flunk
  semantics), or, if a genuinely proxy-less child case exists, state which one
  and cite it. At minimum drop the "which stays alive" claim.

---

## Medium Violations (SUGGESTION)

### [S1] An assertion that cannot fail
- **File**: `test/brando_admin/live/form_recovery_test.exs:65`
- **Code**: `refute_received {:EXIT, ^proxy, _}`
- **Confidence**: DEFINITE
- **Fix**: `stub_view_with_live_proxy/0` `spawn`s an unlinked process that
  `Process.sleep(:infinity)`s and is only killed in `on_exit`. It can never send
  the test process an `{:EXIT, …}`, so this line passes unconditionally and pins
  nothing. Drop it, or link the stub proxy so the refutation has content.

### [S2] Dep source cited by line number with no version pin
- **File**: `test/support/live_case.ex:99` and `:141` (`client_proxy.ex:542-545`)
- **Confidence**: LIKELY
- **Fix**: the same file pins `view.ts:2434-2450` *together with the
  `phoenix_live_view` version it was read against* (`form_recovery_test.exs:80-83`),
  precisely because nothing makes a drifting mirror fail. These two citations get
  no such pin. Pin the version the same way. (Both are accurate against the
  currently vendored dep — verified.)

### [S3] Iron Law #19 — change-narration in comments
- **Files**:
  - `test/brando/plugs/lockdown_test.exs:2-7` — "Phase 5 gave the restore a
    correct implementation (`put_test_env/2`) without making the concurrency
    correct". The durable fact is the first sentence (these tests mutate global
    `:brando, :lockdown`, hence `async: false`); the rest is audit history.
  - `test/support/live_case.ex:136-138, 143-144` — "…is precisely what the old
    `flush_exits/0` did wrong", "this used to return `:ok` whenever the proxy was
    still alive".
  - `mix.exs:82` — "So they were shipped and never evaluated, which is reason
    enough on its own."
- **Confidence**: REVIEW
- **Fix**: keep the invariant, move the "what it used to do / which phase changed
  it" to the commit message. Noting the house style here is deliberately
  discursive — flagged because #19 names this shape explicitly, not to force a
  rewrite. Verified while checking: the lockdown comment's factual claim holds
  (`Brando.Plug.Lockdown` is the only reader of `:lockdown`/`:lockdown_until`,
  and no other test exercises it), as does `mix.exs`'s `priv/` list
  (`priv/templates/brando.install/{deployment.cfg,fabfile.py,.envrc.prod}` all
  exist).

### [S4] The framing corrected at `utils.js:29` survives verbatim 14 lines down
- **File**: `e2e/e2e/playwright/utils.js:43`
- **Code**: `// Replaces flat 1200–1500ms sleeps.`
- **Confidence**: REVIEW
- **Fix**: `awaitBlockShip` does exactly what `awaitBlockDebounce` does — it
  *narrows* a sleep to `BLOCK_SHIP_SETTLE_MS + 50` and adds `syncLV`. "Replaces"
  is the same word that was judged to read as removal at line 28. The plan
  scoped S3 to one sentence deliberately; noting it because the correction is
  now inconsistent within one file.

### [S5] `key_available?/2`'s doc is honest about providers, silent about no-CDN
- **File**: `lib/brando/cdn/cdn.ex:381-399`
- **Confidence**: REVIEW
- **Fix**: the name and the `@doc` do match the return (`true` only on a
  definitive `{:error, :not_found}`) — naming honesty passes, and failing closed
  here is correct: the caller (`utils.ex:1182`) renames rather than blocks. What
  the doc does not say is that `head_object/2` is called unconditionally, with no
  `cdn.enabled` guard: for a `field_cfg` without CDN, `get_s3_config/2`'s
  catch-all (`cdn.ex:114-124`) does `Map.from_struct(nil)` and raises. That is
  pre-existing and unchanged by this diff, but the inversion makes the
  every-upload-gets-a-suffix consequence newly reachable for any provider or
  transient failure that is not a 404 — which the doc *does* state for providers
  and timeouts. One sentence on the disabled-CDN path would close it.

Minor, not counted: `test/brando/utils_test.exs:557` asserts only
`!= @wanted_key` for the occupied case, where the 403 case pins the full
`~r|logo-[a-z0-9]+\.jpg$|`. The weaker assertion would pass on a garbage key.

---

## Pre-existing code outside the diff
Not deep-analyzed per scope: `build_upload_key/2` has no in-repo production
caller (public API for consuming apps), and the three video uploaders still
disagree on missing-credential behaviour (Mux/Bunny raise, Cloudflare returns
`{:error, :not_configured}`) — already recorded in the Phase 6 plan's Risks.
