## Requirements Coverage (from Plan file .claude/plans/form-audit/phase-5-plan.md)

| # | Requirement | Status | Evidence |
|---|-------------|--------|----------|
| W2a | Restore `trap_exit` in `kill_live/1` (capture/restore, nested-safe) | MET | `test/support/live_case.ex:99-116` captures `prior_trap?`, restores after drain; regression test `test/brando_admin/live/form_recovery_test.exs:44-49` |
| W2b | Narrow `flush_exits` to the killed proxy only | MET | `test/support/live_case.ex:118-132` `await_proxy_exit/1` receives only `{:EXIT, ^proxy_pid, _}` |
| W2-verify | Mutation-verify the leak was hiding a real failure | PARTIAL | Regression test kept (`form_recovery_test.exs:44-49`) proves current behaviour, but no RED/GREEN evidence found in scratchpad for this specific test; throwaway (if any) not present in diff — cannot confirm it was actually run against pre-fix code |
| W6 | Selects: first option for single-select, `[]` for multi-select | MET | `test/support/live_case.ex:243-256` `selected_option/3`, gated on `multiple?` |
| S3 | Tie `recovery_target/1` to installed LiveView version | MET | `test/support/live_case.ex:283` docstring names 1.2.8; `test/brando_admin/live/form_recovery_test.exs:57-58` asserts `Application.spec(:phoenix_live_view, :vsn) == "1.2.8"` |
| W1 | Translate 404 → `{:error, :not_found}` in `Client.ExAws.head_object/3` | MET | `lib/brando/cdn/client.ex` — head_object impl maps `{:http_error, 404, _}`; test `test/brando/uploads/direct_finalize_test.exs:165-167` |
| W1-doc | Reconcile moduledoc's "thin on purpose" claim | MET | `lib/brando/cdn/client.ex:1-33` moduledoc names why `head_object`/`delete_object` route through the seam and what stays out |
| W1-verify | Mutation-verify against real ExAws pipeline shape | MET | `test/brando/uploads/direct_finalize_test.exs:127-180` stub `http_client`, tests 404→not_found, 403 passthrough, 200 passthrough |
| W3 | Reverse `Keyword.merge` so built `request_opts` win, all 3 uploaders | MET | `lib/brando/videos/uploaders/mux.ex:579`, `bunny.ex:437`, `cloudflare.ex:284-285` all reversed identically |
| S1 | Decide on `uid null: false`; check shipped consumer migrations first | MET | `priv/repo/migrations/20160219000000_test_migrations.exs:295-308` comment; verified against `priv/templates/brando.install/migrations/20240527120834_brando_103_create_blocks_table.exs:6` (`add :uid, :text`, no null:false) and `brando.upgrade/migrations/brando_123_blocks_uid_constraint.exs` (index only, no null constraint) — claim is accurate |
| S2 | Namespace upload-manager form id; confirm no selector depends on old id | MET | `lib/brando_admin/live/upload_manager.ex:658` `id="brando-upload-manager-queue-form"`; CSS keys on `.upload-manager-queue-form` class (`assets/css/components/UploadManager.css:2`), not the id |
| W7a | `partial_block_save_test.exs` asserts surviving sibling content, not just absent errors | MET | `test/brando/content/partial_block_save_test.exs:64-73` region present, references `block_errors/1` returning `:no_block_change` |
| W7b | Re-point Ecto-only assertions at Brando changeset fns | UNCLEAR | Task claims `Page.changeset/5` / control row at `partial_block_save_test.exs:203`, `asset_orphan_test.exs:48,61`; not independently re-verified line-by-line in this pass — file changes present in diff but exact re-point target not confirmed |
| W7-verify | Each rewritten assertion watched RED-then-green | UNCLEAR | No RED/GREEN log found in diff files reviewed; relies on `scratchpad.md` narrative (not machine-verifiable from diff alone) |
| W4 | Sweep `put_env(key, nil)` pattern via shared helper | MET | `test/support/support.ex:29-38` `put_test_env/2`; used at `direct_finalize_test.exs:41`, `utils_test.exs:211`, `uploads_test.exs:364`, `html_test.exs:1112` |
| W5 | Correct overclaiming `config/test.exs` comment | MET | `config/test.exs:7-17` names `head_object`/`delete_object` as routed, and `cdn.ex:311,354,362` as deliberately outside |
| W9 | Document reset requirement on unique-uid migration | MET | `priv/repo/migrations/20260806000001_unique_block_uid_in_test_schema.exs` moduledoc names `unique_violation`/`23505` and the `--reset` fix |
| S4 | Decide on `config`/`test` dirs in hex package `files:` | MET | `mix.exs:75-93` — dropped from `files:` list, comment states dep compilation is always `:prod` so was unreachable |
| W8 | Make `goOffline` explicit via `conn.close(4000, …)` | MET | `e2e/e2e/playwright/utils.js:77` `conn.close(4000, 'e2e: simulated network loss')` |
| W10 | Close multiuser-sync race: B waits to see A's edit before saving | MET | `e2e/e2e/playwright/tests/blocks/block-multiuser-sync.spec.js:81-84` waits on textarea value before B's save/click sequence at :86-92 |
| 5E-verify | E2E baseline is 107, not 108 | MET | `playwright test --list` (re-run in this review) → `Total: 107 tests in 37 files`, matching the plan's self-correction |
| S5 | Trace suite stdout noise — was Logger.error, not IO.inspect/dbg | MET | `git diff HEAD~6 -- lib/brando/blueprint/error_translator.ex` shows old code was `Logger.error("""#{inspect(form, pretty: true)}""")`, not `IO.inspect`/`dbg`; new version at `lib/brando/blueprint/error_translator.ex:62-67` |

**Summary**: 18 MET · 0 PARTIAL(strict) · 0 UNMET · 2 UNCLEAR (W7-verify counted separately below)

Corrected tally: **18 MET · 1 PARTIAL (W2-verify) · 0 UNMET · 2 UNCLEAR (W7b, W7-verify)**

Notes:
- All 15 triage items (W1-W10, S1-S5) map to at least one MET sub-task; no item is UNMET.
- No scope creep identified beyond what the plan's own "Risks" section already flags (W3 pulling in `cloudflare.ex:283` for consistency, which the plan explicitly authorizes).
- W2-verify and W7-verify are process claims (RED-then-restore) that cannot be confirmed from the diff alone — the diff shows only the end state (a passing regression test / rewritten assertions), not the transient failing run. This is a limitation of static diff review, not necessarily evidence the verification didn't happen.
