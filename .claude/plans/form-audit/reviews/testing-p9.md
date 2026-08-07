# Test Review: Phase 9 (9B + 9D)

## Summary
Both changes are solid. `provider_client_test.exs` correctly pins the raise
contract with type + message regex for all three providers, symmetrically.
The new e2e spec (`the recovery key follows the entry across save-and-continue`)
genuinely exercises the `push_patch` path — verified against source
(`form.ex:2977` push_patches create+save-and-continue; `hooks.ex:46`
comment matches; `block_field.ex:1478` re-renders `data-entry-id`) — and its
comment's factual claim about the push_patch path holds up this time. One
reintroduced fixed wait is the only real issue found.

## Iron Law Violations
None (async: false in provider_client_test.exs is justified — mutates
`Application.env` via `with_config`, restored with `on_exit`; correctly not
async).

## Issues Found

### Critical
None.

### Warnings
- `e2e/e2e/playwright/tests/blocks/block-recovery.spec.js:235` —
  `await page.waitForTimeout(750) // let the post-save re-seed land` is a
  reintroduced fixed wait, which AGENTS.md/prior phases record as
  deliberately removed from block specs in favor of real conditions. This
  sits in the crux C4 test. Replace with a condition wait — e.g. poll/assert
  on `hookEl` gaining a numeric `data-entry-id` (`await expect.poll(...)` or
  `await expect(hookEl).toHaveAttribute('data-entry-id', /^\d+$/)`) instead
  of the attribute read that currently happens right after the sleep
  (line 240).

### Suggestions
- `e2e/e2e/playwright/tests/blocks/block-recovery.spec.js:215-258` — the
  test demonstrates the storageKey scoping mechanism on a single entry's
  new→persisted transition (which is the only real push_patch path per the
  code), so it isn't vacuous, but it never puts a second entry's distinct
  data in play to directly observe "no leak." Given the code path genuinely
  only involves one entry transitioning identity, this is acceptable as-is;
  flagging only because the WHY-context frames C4 as a cross-entry leak and
  a reader might expect two concurrently-open entries.
- `test/brando/videos/provider_client_test.exs` — no issues; `with_config`
  correctly restores via `Application.fetch_env`/`on_exit` (not a plain
  `put_env` without restore), and the doc comment about restoring "no key"
  vs `nil` shows this was already debugged once. `req_options` precedence
  tests correctly reuse the shared `ReqOptions` seam per `bd5b4fb41` rather
  than ad-hoc mocking. All three providers' "missing credentials" tests are
  symmetric (Mux/Bunny/Cloudflare) with type + message-regex assertions,
  not bare `assert_raise RuntimeError`.

## Pre-existing (unrelated to this diff)
None noted in scope.
