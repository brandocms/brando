# Test Review: Phase 8 (`git diff HEAD~5 -- test`)

Scope: `test/brando_admin/live/form_recovery_test.exs`, `test/support/live_case.ex`,
`test/brando/videos/uploaders/req_options_test.exs`,
`test/brando/videos/provider_client_test.exs`, `test/brando/plugs/lockdown_test.exs`,
`test/brando/utils_test.exs`.

## Summary

The four claims I could settle from source are: SEC-1-test sound, W-2-test sound
(it does inspect the wire), W-4c's mutation comments accurate **except one**, S-2
and S-4 done. The two remaining problems are both *comments that name a mutation
which would not actually produce the stated RED* — the exact defect class Phase 8
was written to close. No BLOCKER; three WARNINGs.

## Iron Law Violations

None. Every Application-env-mutating file is `async: false`
(`req_options_test.exs:11`, `provider_client_test.exs:23`, `lockdown_test.exs:7`,
`utils_test.exs:2`); `Brando.LiveCase` documents and enforces non-async. No Mox
global mode, no mocked internals. `live_case.ex:223`'s `Process.sleep(20)` is a
bounded poll with a deadline and a `flunk`, not a timing guess.

## Issues Found

### Critical

_none_

### Warnings

- [ ] **`form_recovery_test.exs:62-64` — the named mutation does not redden the
      assertion.** The comment on `refute Process.alive?(view.pid)` claims it
      "goes RED if the two waits are ever reordered". It does not.
      **Mutation that would NOT redden it:** in `live_case.ex:147-156`, move
      `await_proxy_exit(proxy_pid)` above the `receive {:DOWN, …}` block.
      `Process.exit(pid, :kill)` (`:148`) still runs first, so by the time
      `await_proxy_exit/1` flunks 500ms later the view is long dead and the
      `refute` passes. The same holds for "the flunk moves ahead of the kill" as
      written — only moving the *kill itself* after the proxy wait (or deleting
      it) reddens this line. The assertion is genuinely a subject assertion
      (RED if `kill_live/1` stops killing); the comment claims more coverage
      than it has. Narrow the comment to the mutation that is true.

- [ ] **`form_recovery_test.exs:123-129` — the `:killed` reason claim is not
      supported by the cited runtime, and I could not confirm the plan's
      measurement.** The comment says a root death "reports a different reason
      and reddens this line", and the plan records measuring
      `{:proxy_stopped, :shutdown}`. But `client_proxy.ex:542-545` propagates the
      monitored view's reason **verbatim** (`{:stop, reason, state}`).
      **Mutation that would NOT redden it:** replace `Process.exit(child.pid, :kill)`
      at `:121` with `Process.exit(view.pid, :kill)` — the root's DOWN carries
      `:killed`, `:542` stops the proxy with `:killed`, and
      `assert outcome == {:proxy_stopped, :killed}` passes. If the measured
      `:shutdown` is real it must come from a different path (child teardown
      racing the root's DOWN), i.e. it is order-dependent and not the causal link
      the comment describes. Either record the mechanism that produces
      `:shutdown` next to the assertion, or drop the "a root crash reports a
      different reason" sentence and lean on the three premises at `:109-111`,
      which are the part that actually restores causation.
      (The premises themselves are correct and do the job.)

- [ ] **`req_options_test.exs:115-117` — the named mutation reddens the test for
      the wrong reason and makes it hit the network.** The comment says the
      allowlist mutation `Keyword.take(configured || [], [:headers, :method, :url, :json])`
      means "the stub then sees the built header and this reddens". That
      allowlist drops `:plug` as well as `:auth`, so the stub is never invoked at
      all: `Req.request/1` issues a real GET to `https://example.com/videos` and
      the test reddens on `assert {:ok, %{status: 200}}` (or a transport error
      offline). Under this file's own standard — "watched go RED", for the stated
      reason — this is not the stated reason. Fix by naming
      `Keyword.take(configured || [], [:headers, :method, :url, :json, :plug])`,
      which leaves the transport stubbed and reddens on the header assertion at
      `:126`, as claimed.

### Suggestions

- [ ] **`req_options_test.exs:60-63` and `req_options.ex:70-74` conflate two
      different `nil`s.** Both say `Application.put_env(key, nil)` beats the `[]`
      default "so `Keyword.get(nil, :req_options)` would raise", and present
      `|| []` as the guard for it. `|| []` guards `req_options: nil` (what
      `:68` tests); the `Keyword.get(nil, …)` case is `put_env(:brando, provider, nil)`,
      which **`merge/2` does not defend at all** — it raises, and no test covers
      it (`provider_client_test.exs:37-41` describes that case correctly). Split
      the two sentences so the doc claims only what the code does.
- [ ] **`form_recovery_test.exs:139-140` — the `demonitor` calls sit after
      `assert outcome == …` (`:137`), so a failing assertion skips them.** Move
      both into the existing `after` block alongside the `trap_exit` restore.
      Harmless today (test process exits), but it is the same shape S-2 was
      raised about.
- [ ] **`provider_client_test.exs:199-202` couples the security assertion to log
      text (`=~ "302"`).** The credential claim is fully carried by
      `assert_received`/`refute_received` at `:204-205`; a reworded Bunny error
      message reddens the security test for a formatting reason. Consider
      `capture_log(...)` without the `=~`, or assert on the error tuple instead.
- [ ] **`live_case.ex:173-179` (`await_proxy_exit/1`) is sound** — pinned pid, no
      blanket drain, `flunk` on timeout, no vacuous pass; timeouts can only
      produce false failures, never false passes. One residual coupling worth a
      line: it depends on `live/2` **linking the test process** to the proxy. If
      that ever stops being true the helper flunks every call, which reads as a
      LiveView hang rather than as a harness assumption.

## Verified as claimed (no action)

- **W-4a** both parts present: `refute Process.alive?(view.pid)` (`:65`) and the
  proxy line explicitly labelled a fixture premise (`:67-76`).
- **W-4b** `child.pid != view.pid`, `Process.alive?(view.pid)`,
  `Process.alive?(proxy_pid)` all present at `:109-111`; reason pinned at `:137`
  (but see WARNING above on what the pin distinguishes).
- **W-4c** mutations checked against `req_options.ex:77-84`. `:32` (flip merge
  order) reddens `:36` and **only** `:36` — I re-checked all four others by hand.
  `:65` (drop `|| []`) reddens both nil tests; `:74` (drop the `[]` default from
  `get_env/3`) reddens `:83` alone, because with the key present `get_env`
  returns the stored list either way. The plan's self-correction is accurate and
  the shipped comments state it.
- **W-2-test** does inspect the wire: the header assertion is inside the
  `Req.Test` stub (`:126`) and is reached because `assert {:ok, %{status: 200}}`
  (`:144`) proves the stub ran. `Req.Test`'s plug runs inline in the test
  process, so the raise propagates. `:143` correctly documents that the keyword
  list is *not* where the overwrite happens.
- **SEC-1-test** would catch the leak. With `redirect: false` removed from
  `bunny.ex:440/443/446`, Req's redirect step re-runs through the same `plug`
  stub and `remove_credentials_if_untrusted/3` strips only `authorization`/`:auth`,
  so `{:request, "evil.example.com", ["bunny-key"]}` lands in the mailbox and
  `refute_received` (`:205`) reddens. Both messages are in the mailbox
  synchronously before `initiate_upload/2` returns, so no `assert_receive`
  timeout race exists.
- **S-2** both refs demonitored with `[:flush]` (`:139-140`) — see suggestion.
- **S-4** `req_options_test.exs:89-97` restores the *unset* case by
  `Application.delete_env/2`, not by storing `nil`. Correct, and matches
  `put_req_options/1` (`:19-29`) and `Brando.Test.Support.put_test_env/2`
  (`support.ex:29-39`).
- **`lockdown_test.exs` / `utils_test.exs`**: the `put_test_env/2` conversion is
  correct — absent keys are deleted rather than "restored" to `false`/`nil`, and
  restore runs from `on_exit` so a failed assertion no longer leaks env. The
  mid-test `Application.put_env(:brando, :lockdown, false)` at
  `lockdown_test.exs:121` is deliberate and still covered by the `on_exit`
  delete.

## Pre-existing (one line each)

- `test/brando/plugs/lockdown_test.exs:151-168` — "lockdown pass with
  lockdown_authorized" cannot fail on the password path: `LockdownPlugAuth`
  seeds a `:superuser` session which passes lockdown regardless, and the second
  `call("/")` builds a fresh conn that carries no session cookie from the first;
  deleting both `put_test_env(:lockdown_password, …)` and `?key=my_pass` leaves
  it green.
- `test/support/live_case.ex:207-226` — `await_selector/3` polls with
  `Process.sleep(20)`; bounded and flunking, but it is the one sleep in the
  harness.
- `test/brando/utils_test.exs:170-260` — one very long `test` block asserting
  ~20 unrelated `img_url/3` behaviours; a failure early hides the rest.
