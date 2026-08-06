# Iron Law Violations Report — Phase 5

## Summary
- Files scanned (deep): `test/support/live_case.ex`, `lib/brando/cdn/client.ex`,
  `test/brando/content/partial_block_save_test.exs`,
  `test/brando/uploads/asset_orphan_test.exs`,
  `test/brando/uploads/direct_finalize_test.exs`, `config/test.exs`,
  `priv/repo/migrations/20260806000001_unique_block_uid_in_test_schema.exs`,
  `.claude/plans/form-audit/phase-5-plan.md`, `test/support/support.ex`,
  plus the 9 files claimed to use `put_test_env/2` (spot-checked all).
- Iron Laws checked: theatre/no-fake-work, claims-match-reality,
  no-silent-scope-change/dead-code, error-handling honesty, doc truthfulness.
- Violations found: 0

## Findings

No violations. Detail on what was verified:

- **Theatre check** — `partial_block_save_test.exs`, `asset_orphan_test.exs`,
  `direct_finalize_test.exs` all drive real Brando changeset/context code
  (`Page.changeset/5`, `Content.Blocks`, `Uploads.finalize_direct/3`), not
  test-invented changesets. `block_errors/1` (partial_block_save_test.exs:73-82)
  correctly distinguishes `:no_block_change` (vanished block — the real
  data-loss shape) from `[]` (cast with no errors), so it cannot be satisfied
  by the defect it exists to catch.
- **`flush_exits/0` → `await_proxy_exit/1`** — confirmed no remaining callers
  of `flush_exits` anywhere (`Grep` clean); the sole caller in
  `live_case.ex:118` uses the new function, scoped to `view.proxy`'s pid only.
- **Local `restore_env` sweep (W4)** — `test/brando/ai_test.exs:107-108` still
  has a local `restore_env/3` helper, but this is correct: it already
  distinguishes the nil/absent case, is confirmed in `testing-p4.md:89-92` as
  "verified correct, no action," and it operates on two different OTP apps
  (`:brando` and `:req_llm`), which `Brando.Test.Support.put_test_env/2`
  (hardcoded to `:brando`, `support.ex:29`) cannot express. Not a leftover —
  out of scope by design. The four sites actually claimed migrated
  (`direct_finalize_test.exs`, `utils_test.exs`, `uploads_test.exs`,
  `html_test.exs`) all confirmed using `put_test_env/2`.
- **`Client.ExAws` 404 → `:not_found`** (`lib/brando/cdn/client.ex:96`) — honest:
  only 404 is translated, moduledoc states the known limit (403-masked-404 on
  some providers), and `direct_finalize_test.exs`'s "Client.ExAws meets the
  behaviour's contract" block asserts 403 passes through *untranslated* — the
  narrow scope is enforced by a test, not just claimed in prose.
- **`await_proxy_exit/1` "no exit = success"** (`live_case.ex:131-142`) — honest:
  gated on `Process.alive?(proxy_pid)`; if the proxy died without a signal it
  `flunk`s rather than passing silently.
- **Doc truthfulness** — `config/test.exs:7-15` names the two calls that
  actually route through the mock and explicitly disclaims the calls that
  don't (`cdn.ex:311,354,362`). The migration moduledoc documents the
  no-dedupe assumption and the exact Postgres error an operator would hit
  without `--reset`. Both match the code.
- **Plan claims** — spot-checked every `[x]` item in `phase-5-plan.md` against
  code for 5A/5B/5D; all "done:" notes match what shipped (trap_exit restore,
  narrowed drain, 404 translation + doc, req_options merge order not
  independently re-verified here — outside the listed focus files).

## Pre-existing (outside diff, one-line only)
- None flagged — task scoped review to the listed diff files only.
