## Requirements Coverage (from Plan `.claude/plans/form-audit/phase-8-plan.md`)

| # | Requirement | Status | Evidence |
|---|-------------|--------|----------|
| 1 | 8A B1-fix — five interior citations → function heads (`put_view/3`, `:DOWN` clause, `fetch_view_by_pid/2`, `recursive_detect_added_or_removed_children/4` by name) | MET | `test/support/live_case.ex:95-105`; head-vs-interior rationale at `:107-112`; `await_proxy_exit/1` comment converted at `:166-171` |
| 2 | 8A B1-record — `phase-7-plan.md:147` amended: verification *introduced* the defect, original claim quoted, record kept | MET | `.claude/plans/form-audit/phase-7-plan.md:146-147` (original claim quoted verbatim, "a verification pass *introduced* the defect" stated, line not deleted) |
| 3 | 8A B1-guard — sentence that the version pin catches drift, not authorship | MET | `test/support/live_case.ex:119-126` |
| 4 | 8B W-1 — `key_available?/2` doc drops the `Map.from_struct/1` blow-up claim; "raises before any network call" retained | MET | `lib/brando/cdn/cdn.ex:424-440`; conclusion retained at `:437-440` (measured mechanism: `cdn_config.bucket` `BadMapError` at `:429`) |
| 5 | 8B W-2 — doc leads with the general pass-through rule, keys as examples, incl. `:redirect_trusted`, `:form`/`:form_multipart`, `:json`, `:connect_options`/`:finch` | MET | `lib/brando/videos/uploaders/req_options.ex:31-40` (rule first, "not an allowlist"), examples `:44-64`; `:base_url` inert note `:66-68`; allowlist decline retained `:70-74` |
| 6 | 8B W-2-test — `Req.Test` round-trip asserting a configured `:auth` reaches the wire | MET | `test/brando/videos/uploaders/req_options_test.exs:124-146` (stub asserts `Bearer hijacked`, real `Req.request/1`) |
| 7 | 8C W-3a — both `live_case.ex` blocks present tense, B1-guard folded in | MET | `test/support/live_case.ex:89-127` (no role argument narrated as history; `:113-118` present-tense why-no-role) and `:161-171` |
| 8 | 8C W-3b — `form_recovery_test.exs` present tense; "a stub proxy cannot see this at all" retained | MET | `test/brando_admin/live/form_recovery_test.exs:88-97` (retained at `:96-97`); past-tense `await_proxy_exit` narration removed at `:53-54` |
| 9 | 8D W-4a — decide label-vs-replace **and say why in the comment** | MET | subject assertion `refute Process.alive?(view.pid)` at `form_recovery_test.exs:66`; fixture premise labelled with reasoning `:67-77` |
| 10 | 8D W-4b — `child.pid != view.pid`, root alive, proxy alive, and assert the `:DOWN` reason | MET | `form_recovery_test.exs:112-114` (three premises), `:137` `assert outcome == {:proxy_stopped, :killed}` |
| 11 | 8D W-4c — one comment per test naming its mutation, each run | MET | five `MUTATION:` comments at `req_options_test.exs:32, 45, 65, 74, 115`; run record + self-correction in `scratchpad.md:1229-1237` |
| 12 | 8E SEC-1 — `redirect: false` on all three `request_opts` branches | MET | `lib/brando/videos/uploaders/bunny.ex:440, 443, 446`; no-redirect-dependency check stated `:434-438` |
| 13 | 8E SEC-1-test — `Req.Test` 302-to-another-host stub | MET | `test/brando/videos/provider_client_test.exs:176-205` (`assert_received {:request, "video.bunnycdn.com", ["bunny-key"]}`, `refute_received {:request, "evil.example.com", _}`) |
| 14 | 8E SEC-1-note — why Mux/Cloudflare need no equivalent | MET | `bunny.ex:425-427`; also `provider_client_test.exs:163-172` and CHANGELOG |
| 15 | 8E CHANGELOG under Fixes — names the leak, stock-default condition, config cannot re-enable | MET | `CHANGELOG.md:69-88` (leak `:69-75`, "stock defaults" `:75`, "cannot be switched back on" `:82-85`, Mux/CF note `:87-88`) |
| 16 | 8F S-1 — comment saying the keyword-list `:s3` shape is not reachable as stated; no behaviour change | MET | `lib/brando/cdn/cdn.ex:127-140` (keyword-list CDN config raises in `config/2` at `:72`; keyword-list `:s3` unwritten in repo); guard unchanged |
| 17 | 8F S-2 — `Process.demonitor(ref, [:flush])` | MET | `form_recovery_test.exs:139-140` (both refs) |
| 18 | 8F S-3 — duck-typing coupling stated next to the version assertion | PARTIAL | coupling stated at `form_recovery_test.exs:357-364` and it cross-references the version assertion, but it sits at the stub definition, not adjacent to the assertion at `:152` |
| 19 | 8F S-4 — `fetch_env` + `on_exit` restore | MET | `req_options_test.exs:19-29` (helper) and `:83-92` (unset-provider test) |
| 20 | 8F S-5 — scratchpad corrected to 1280 tests and 43/27/0 | MET | `scratchpad.md:1061, 1063`; no `1278` remains in the file |
| 21 | 8F S-6 — `@spec` on `ReqOptions.merge/2` | MET | `lib/brando/videos/uploaders/req_options.ex:76` |
| 22 | 8G E2E run recorded in `scratchpad.md` with its date (2026-08-06, 107/0, 8.8m) | MET | `scratchpad.md:1185-1191` |
| 23 | RED evidence in tree — W-2-test actually run | MET | `req_options_test.exs:115-122` names the `Keyword.take` mutation; `scratchpad.md:1177-1181` "Every one of the five per-test mutations was run and watched go RED" |
| 24 | RED evidence in tree — W-4b actually run | UNCLEAR | asserted only in the plan annotation (`phase-8-plan.md:195`, `{:proxy_stopped, :shutdown}`); no scratchpad or in-test record of that run — plan claims are not evidence |
| 25 | RED evidence in tree — W-4c each of five mutations run | MET | `scratchpad.md:1229-1237` records per-mutation outcomes incl. a correction found by running them |
| 26 | RED evidence in tree — SEC-1-test run (remove `redirect: false`, watch credential appear) | MET | `scratchpad.md:1243-1248` (`{:request, "evil.example.com", ["bunny-key"]}`, `Req.TooManyRedirectsError`); test comment `provider_client_test.exs:173-175` |
| 27 | Traceability — all 13 finding→task rows have a landed task | MET | rows 1-22 above cover B1, W-1..W-4, S-1..S-6, SEC-1 group, E2E; none unaddressed |

**Summary**: 25 MET · 1 PARTIAL · 0 UNMET · 1 UNCLEAR

SUMMARY: 25 MET, 1 PARTIAL, 0 UNMET, 1 UNCLEAR
