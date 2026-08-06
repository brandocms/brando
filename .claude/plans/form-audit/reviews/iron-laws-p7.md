# Iron Law Violations Report — Phase 7 (`form-audit`)

## Summary
- Files scanned: 9 changed (lib 3, test 5, mix.exs) + 1 new untracked test
- Iron Laws checked: 26 of 26 (LiveView/Ecto/Oban/security laws: no new surface in this diff)
- Violations found: 6 (2 BLOCKER, 2 WARNING, 2 SUGGESTION)

The only Iron Law with live findings in this diff is **#19 / "comments are not
commit messages"**, extended by this audit's own standard: *a comment or @doc
stating a false invariant is a defect of the same class as a code bug.* Two of
the newly-written prose blocks state something the code does not do.

Every `file:line` citation in the new prose was opened and read. Results below;
verified-correct citations are not listed.

## Critical Violations (BLOCKER)

### [#19] Three of five `client_proxy.ex` citations in the new `kill_live/1` @doc are off by one
- **File**: `test/support/live_case.ex:96-100`
- **Code**:
  ```
  monitors every view it registers (`put_view/3`, `client_proxy.ex:848`) and keys
  them all in one `state.pids` map (`:856`); children go through the same
  function (`:1001`); ... (`:542-545` → `fetch_view_by_pid/2`, `:908-912`)
  ```
- **Confidence**: DEFINITE (read against `deps/phoenix_live_view` @ `@version "1.2.8"`, matching `mix.lock:87`)
- **Mismatch**, in `deps/phoenix_live_view/lib/phoenix_live_view/test/client_proxy.ex`:

  | Cited | Claim | Actual line | What the cited line really is |
  |---|---|---|---|
  | `:848` | `Process.monitor(pid)` | **849** | `new_view = %{view \| module: module, …}` |
  | `:856` | `pids: Map.put(state.pids, …)` | **857** | `\| views: Map.put(state.views, …)` — the *views* map, not `pids` |
  | `:908-912` | `fetch_view_by_pid/2` | **909-913** | `:908` is a blank line |
  | `:1001` | child reaches `put_view/3` | 1001 | correct |
  | `:542-545` | `{:DOWN, …}` → `{:stop, reason, state}` | 542-545 | correct |

  The `:856` case is the material one: the doc names `state.pids` and points at
  the line that writes `state.views`.
- **Aggravating**: `phase-7-plan.md:147` records S-2 as having *re-verified* these
  against the vendored 1.2.8 and as having **corrected** the monitor line from
  `:849` to `:848` — i.e. the verification moved a correct citation to an
  incorrect one. The same `:848/:856` pair is repeated in `scratchpad.md`. This is
  the exact failure mode B1 was raised about (a citation to a moving dep that said
  the opposite of what it was cited for), reproduced inside the task that was
  meant to close it.
- **Fix**: `:848 → :849`, `:856 → :857`, `:908-912 → :909-913`. The version pin
  (S-2) is correct and worth keeping; it is what makes this checkable.

### [#19] `key_available?/2`'s new @doc names a raise path that the same working tree just replaced
- **File**: `lib/brando/cdn/cdn.ex:407-412`
- **Code**:
  ```
  with `:cdn` absent it falls through `get_s3_config/2` to the `Brando.Images`
  `:s3` fallback and blows up on `Map.from_struct/1` when that is unset too
  ```
- **Confidence**: DEFINITE
- **Mismatch**: S-6 (Phase 7E, same uncommitted diff) rewrote that clause.
  `cdn.ex:114-125` now tests `if !s3_config` **before** `Map.from_struct/1` and
  raises `"Missing S3 config. The field config has no ':cdn' …"`. There is no
  longer any path through `get_s3_config/2` that reaches `Map.from_struct(nil)`.
  The @doc documents the pre-S-6 code. The plan itself records the S-4 probe as
  having been done *"rather than assumed"* (`phase-7-plan.md:248`) — but the probe
  was run against the shape S-6 then removed, and the doc was not re-read after.
- **Correct half**: the `cdn_config.bucket` branch (`cdn.ex:429`) does still raise
  when `:cdn` is nil and the `Brando.Images` `:s3` fallback *is* set, and the
  ordering claim (raises before any network call) holds.
- **Fix**: replace the `Map.from_struct/1` clause with the explicit config raise
  now in `get_s3_config/2` (`cdn.ex:123-125`). Both raises remain, so the "either
  way it raises" conclusion survives — only the named mechanism is wrong.

## High Violations (WARNING)

### [#19] "What still reaches past it" is presented as a complete enumeration and is not one
- **File**: `lib/brando/videos/uploaders/req_options.ex:29-45`
- **Confidence**: LIKELY (this is the near-exhaustive-list-as-complete class the
  phase targets; the doc does not say "among others")
- **Verified correct**: `req/steps.ex:236, 240, 244` (`Req.Request.put_header/3`
  in the auth step) and `:123` (`put_base_url/1` no-ops on a URL with a scheme)
  are all **exact**, against `req 0.7.2` (`mix.lock:97`). `:auth`, `:plug`,
  `:adapter`, `:params` all genuinely reach past the merge.
- **Not named, same class**:
  - `:form` / `:form_multipart` — `encode_body/1` is a `cond` and tests them
    **before** `:json` (`deps/req/lib/req/steps.ex:486, 490` vs `:497`). All three
    providers build `json: body` on a POST (`mux.ex:567`, `bunny.ex:425`,
    `cloudflare.ex:282`), so a configured `form:` silently replaces the request
    **body** the provider built — the same shape of hazard as `:auth`, and
    arguably worse than `:params`.
  - `:connect_options` / `:finch` — transport replacement, the class the doc
    already calls out as `:plug` / `:adapter`.
  - `:path_params` — rewrites the built `:url` via `put_path_params/1` (harmless
    for today's URL shapes, which is a statement worth making rather than omitting).
- **Fix**: either add `:form`/`:form_multipart` (with the `steps.ex:486` cite) and
  fold `:connect_options`/`:finch` into the transport bullet, or scope the heading
  ("the ones that matter for the credentials this merge is protecting") so it stops
  reading as exhaustive.

### [#19] Phase 7's own S-3 ban on change-narration is reintroduced by Phase 7's own new prose
- **Files**:
  - `test/support/live_case.ex:104-115` — *"An earlier version took a `:root | :child` role from the caller and skipped the wait for a child…"*, *"What the Phase 5 review actually caught was `await_proxy_exit/1` returning `:ok` on timeout"*, *"that is how this citation failed the first time"*
  - `test/brando_admin/live/form_recovery_test.exs:74-82` — *"An earlier version skipped the wait for a child, on the reading that…"*
  - `test/brando_admin/live/form_recovery_test.exs:68-70` — *"Without that, a caught flunk leaks it into every later line"* (this one is fine — it states an invariant, not a history)
- **Confidence**: REVIEW → the classification is a judgement call, the pattern is not
- **Mismatch**: S-3 (`phase-7-plan.md:152`) is written as *"State what the code does,
  not what it used to do"*, and names `live_case.ex:136-144` and
  `form_recovery_test.exs:52-58` as two of its four sites — both rewritten by B1-fix
  and both landing with fresh past-tense narration of the deleted `:root | :child`
  role. `live_case.ex:108` additionally references a review phase ("the Phase 5
  review"), which is process history that git carries.
- **Counter-argument, acknowledged**: the *reason* the proxy is awaited
  unconditionally is a durable footgun — a future reader who reintroduces a role
  argument repeats the bug. That content should stay.
- **Fix**: keep the invariant, drop the chronology. E.g. *"The proxy is awaited for
  every view, including children: the runtime makes no root/child distinction on
  this path (citations above). A role argument here would be a distinction the
  runtime does not make."* No "earlier version", no phase numbers. Same for
  `form_recovery_test.exs:74-82` — the test title already says what it pins.

## Medium Violations (SUGGESTION)

### [#19] The test that claims to make the `@doc` falsifiable does not test the doc's actual claim
- **File**: `test/brando/videos/uploaders/req_options_test.exs:70-96` (and its
  moduledoc, `:6-9`)
- **Confidence**: REVIEW
- **Mismatch**: the doc's load-bearing claim is *behavioural* — `:auth` **overwrites**
  the `authorization` header the provider built, because Req's auth step uses
  `put_header/3`. The test asserts only that `:auth` survives `Keyword.merge/2`
  into the resulting keyword list (`:92`). That is a property of `Keyword.merge/2`,
  not of Req. If Req changed `put_header/3` → `put_new_header/3` tomorrow, the doc
  would be false and this test would stay green — which is the shape of gap the
  plan's own W-2a rationale says it is closing ("pin the documented-as-reachable
  keys too, so W-1's doc is falsifiable").
- **Fix**: one `Req.Test` stub test in `provider_client_test.exs` shaped like the
  three that already exist there: configure `req_options: [plug: …, auth: {:bearer,
  "hijacked"}]` against Mux or Cloudflare and assert the stub sees `Bearer hijacked`,
  not the built credential. That makes the `put_header` reading go RED on a Req bump.
  Alternatively soften the moduledoc to say it pins pass-through only.

### [#19] `mix.exs` `files:` comment narrates the prior state it was told to stop narrating
- **File**: `mix.exs:96-99`
- **Code**: *"Naming the directory was also actively harmful: … so `"assets"` swept
  in `assets/node_modules/` — gitignored, 120 MB, and 10_976 of the 11_194 `assets/`
  entries it produced."*
- **Confidence**: REVIEW
- **Mismatch**: S-3 (`phase-7-plan.md:157-159`) asked for *"what the list excludes and
  why it is safe"* and explicitly to drop the historical clause. `mix.exs:79-94` does
  that job well. `:96-99` is a past-tense account of the bug being fixed, with the
  measurement from the fixing session — commit-message material.
- **Counter-argument**: the durable fact underneath ("Hex globs the filesystem and
  does not read `.gitignore`") is a real library quirk and should stay.
- **Fix**: keep the quirk as a forward-looking warning — *"Hex globs the filesystem
  and ignores `.gitignore`, so naming a directory here ships everything under it,
  including build artefacts."* Drop the byte counts and the past tense.

## Checked and clear (one line each, no action)

- **Vacuous assertions in new tests (check #3): none found.** `form_recovery_test.exs:66`
  is now `assert Process.alive?(proxy)` and can fail; `:110` asserts
  `outcome == :proxy_stopped` and the 500ms `receive` genuinely branches;
  `utils_test.exs:571-581` rely on Mox strict mode (absence of `expect` *is* the
  assertion) which is a real failure mode, not a vacuous one; the three
  `provider_client_test.exs` precedence tests assert inside a `Req.Test` stub that
  is guaranteed to run by the trailing `assert {:ok, _} = …`.
- **`try/after` semantics (check #5): correct.** `live_case.ex:136-149` — `after`
  runs on the normal return and on the `flunk` raise, so the flag is handed back on
  both paths, and `prior_trap?` makes it compose across repeated calls. The @doc's
  and the comment's claims about it both hold. `Process.flag(:trap_exit, true)` is
  set before `Process.exit/2`, so there is no window where the linked proxy's exit
  can kill the test.
- **Citations verified exact**: `req/steps.ex:236, 240, 244` and `:123`;
  `client_proxy.ex:542-545` and `:1001`; `upload.ex:321-327` (the `overwrite`
  branch, `utils.ex:1186`); `Brando.Type.FileConfig` exists
  (`lib/brando/types/file_config.ex`); `view.ts:2434-2450` and `:2450`
  (`inputs.find((el) => el.type !== "hidden") || inputs[0]`);
  `channel.ex:848-853` (`decode_merge_target/1`); `mix.lock` pins
  `phoenix_live_view 1.2.8` and `req 0.7.2`, and the vendored dep's `mix.exs`
  agrees (`@version "1.2.8"`).
- **`layouts/live.html.heex:2-4`** (`form_recovery_test.exs:78`): three
  `live_render` calls do begin on 2, 3 and 4, but the third spans `:4-8`. Cite
  `:2-8` if precision is wanted; not worth a finding on its own.
- **No LiveView / Ecto / Oban / security Iron Law surface in this diff.** No new
  `mount/3`, no queries, no workers, no `String.to_atom`, no `raw/1`, no
  `handle_event`. The `Oban.insert` / `fragment("? @> ?", j.args, ^args)` calls in
  `cdn.ex:149-156, 192-200` are pinned and pre-existing (unchanged by this diff).

## Pre-existing, one line each

- `lib/brando/cdn/cdn.ex:203-205` — empty `@doc """ """` on `upload_file/3`.
- `lib/brando/uploads.ex:424-428` — `build_direct_filename/2` tests `:random_filename`
  before `:overwrite`; `build_upload_key/2` applies `random_filename` inside
  `get_valid_filename/2` and *then* short-circuits on `:overwrite`. Same result
  today, different branch order — a third divergence in a rule that already has
  three implementations.
- `lib/brando/videos/uploaders/cloudflare.ex:272-273` — returns
  `{:error, :not_configured}` where Mux and Bunny raise; recorded a fourth time in
  `phase-7-plan.md:390-394`, still untriaged.
