# Test Review: commit 2c26cb31b (Phase 0 regression tests)

## Summary

This is unusually strong regression coverage. Every file scrutinised drives the
*real* production code path (the actual `Events.handle_block_event/3` clauses,
the actual `Ops.apply_op/2`/`materialize_root/2`, the actual `block_changeset/3`),
not a reimplementation, and the majority assert on `changeset.changes` /
`Repo.update` round-trips rather than only `apply_changes`. The hand-built
`%Phoenix.LiveView.Socket{}` fixtures were checked against the real
`handle_block_event("validate_block", ...)` clauses in `events.ex:706-825` and
supply exactly the assigns those clauses read — this is a faithful simulation,
not a bypass. No test found that "can't fail."

## Iron Law Violations

None. Sandbox isolation is used throughout (`Brando.ConnCase`), no mocks appear
in these files, no `Process.sleep`.

## Issues Found

### Critical

None found — no test asserts a passing outcome that would also pass against
the pre-fix code path.

### Warnings

- `test/brando_admin/components/form/block/child_diff_test.exs:89-95` — `captured_op/0`
  uses `receive ... after 0 -> flunk(...)`. This is sound *today* because
  `send_update` outside a LiveView process is a synchronous `send(self(), ...)`
  landing in the mailbox before `handle_block_event/3` returns, and each
  `validate/3` call drains exactly one message before the next `validate` call
  produces its next one — so there's no cross-test mailbox leakage risk within
  a test. But this is an internal-detail message shape (`{:phoenix, :send_update, {ref, %{op: op}}}`)
  with zero documentation that it's part of a contract. If `Block.assign_block_form/2`
  changes to batch ops, call `send_update` more than once per validate, or use
  `Process.send_after`, this test will `flunk` loudly (good) but could equally
  start silently matching a stray/earlier message with a different shape if a
  second `send_update` sneaks into the same `handle_block_event` call in a
  future change — worth a comment explaining the exactly-once assumption is
  load-bearing for `after 0` to be safe, not just convenient.

- `test/brando/content/conditional_refs_test.exs:126-139` — "does not carry an
  unsaved ref" documents a **known gap** (unsaved refs inside stripped logic
  are still dropped) rather than proving anything is fixed. That's honestly
  labelled in the plan (line 227-233) as a "known gap," but the test itself
  has no comment saying so — a future reader skimming just this file could
  mistake it for a fixed-behaviour assertion rather than a pinned defect.
  Low severity since the plan documents it, but the test file should say so
  too for anyone auditing test-by-test.

- Blanket `async: false` (all 10 files) — checked against repo convention:
  this matches existing practice for DB-touching tests elsewhere (e.g.
  `orphaned_blocks_test.exs`), so it's not a one-off violation, but it's
  also not clearly justified per-file (none of these tests mutate
  `Application.env`, global config, or use Mox global mode — the only shared
  state is the DB, which `Ecto.Adapters.SQL.Sandbox` with per-test
  ownership already isolates for `async: true`). Given the repo-wide pattern,
  this reads like copy-paste of a convention rather than a considered choice,
  but changing it is out of scope for this review — flagging for awareness,
  not requesting a change here.

### Suggestions

- `ref_media_test.exs` and `child_diff_test.exs` construct
  `%Phoenix.LiveView.Socket{}` by hand with a fixed list of assigns. If the
  real `handle_block_event` clauses start reading a new assign (e.g. a future
  `belongs_to`-dependent branch), these tests will raise `KeyError` rather
  than silently pass-through — that's the correct failure mode, but it means
  the fixture list needs active maintenance. Consider a shared test helper
  (`socket_fixture/2` or similar) shared between `ref_media_test.exs` and
  `child_diff_test.exs`, which currently duplicate near-identical
  `socket_for/2,3` helpers with slightly different assign sets — drift
  between the two is easy to introduce silently.

- `test/brando_admin/components/form/picker_select_test.exs:106-113` — "an
  edit_image with no field is a no-op" doesn't assert `socket.assigns.edit_image`
  or anything else changed appropriately; only checks `form.source.changes == %{}`.
  Fine as written, but a slightly stronger assertion (e.g. that no crash occurs
  and `edit_image` still gets set) would rule out the test passing merely
  because the whole clause silently no-ops on an unrelated exception path.

## Coverage vs Phase 0 plan

All B1/B2/B3/B4/B5/B6/B7/A1/A2 have tests matching or exceeding what the plan
claims (B1's save round-trip, B2's child-merge, B3's `materialize_child`,
B4's `var_attrs/0` completeness guard, B5's honestly-scoped confirmation, B6's
`get_field`-vs-`get_assoc` documentation test, B7's `changes`-based assertion,
A1's 9-test matrix, A2's 4-test matrix). No gaps found beyond the two
explicitly-deferred E2E items the plan itself marks undone (B1's kill-the-LV-pid
E2E, B5's E2E, both correctly left unchecked in `plan.md`).
