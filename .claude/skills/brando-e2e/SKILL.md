---
name: brando-e2e
description: >
  Write, diagnose, and optimize Brando's Playwright E2E tests. Use for browser
  test failures, flaky runs, fixed waits, fixtures, and LiveView synchronization.
  Covers sandbox-bound authentication and readiness across uploads, previews,
  and concurrent editors; not a general browser automation workflow.
---

# Brando E2E tests

Use [AGENTS.md](../../../AGENTS.md) for setup, asset builds, test commands and
the final validation requirements, and [CODING_STANDARDS.md](../../../CODING_STANDARDS.md)
for test isolation and locale coverage. This skill supplies the browser/server
coordination rules those commands depend on.

## Diagnose the failing boundary

Start with the failing test's error, trace and server output. Separate a wrong
locator or missing readiness check from an application race, leaked fixture state,
and infrastructure failure before editing. A visible, enabled control can still
be waiting for its LiveView connection, hook initialization or an async result.
If a real user can hit the same race, investigate the application as well.

Keep the reproduction on the failing spec or test. Use the actual failing CI
trace when the failure is CI-only; a different local failure is not confirmation.
Do not repair a test by hiding errors, skipping its assertion when the control is
missing, forcing a click through an overlay, or increasing retries.

## Wait for the result the next action needs

E2E pages move nothing: CSS motion is cut to 1ms and `prefersReducedMotion()`
skips Web Animations, so there is no animation to wait out. A test about motion
opts in with `withRealMotion(page)` from utils.js before its first navigation.

Fixed sleeps charge their full duration on every execution, loop and retry.
Prefer retrying locator assertions or `expect.poll` for the required state.
Register a response/event wait before the action that triggers it. Keep existing
behavior assertions when removing a wait; a faster pass alone proves little.

The boundaries below are distinct:

| Boundary | Completion evidence |
| --- | --- |
| LiveView connection and acknowledged form events | `syncLV(page)` from [utils.js](../../../e2e/playwright/utils.js). It checks every mounted LiveView and loading classes. |
| A client debounce or focusout settle timer | `syncLV` can return before the event is sent. Prefer the resulting value/status; use the existing `awaitBlockDebounce` / `awaitBlockShip` helpers only where their documented timer boundary is needed. |
| Upload delivery and image processing | UploadTrigger enqueues into the target's configured/current/default folder immediately; only an explicit destination change opens the folder chooser. Assert the image/count/status in the owning field. The UploadManager's transport finishing is not proof that the block received a processed image. |
| Image editor initialization | The drawer and canvas can be visible before the image has loaded. Wait for `#image-editor-hook` to have `aria-busy="false"` and nonzero dimensions in `#image-editor-dimensions` before cropping or saving; a failed image load also clears the busy state. |
| Preview updates | Assert the expected content in the preview iframe. Settling the parent LiveView only covers the sender; DOM quietness or an already-visible iframe does not establish receipt of this update. |
| Multi-user changes | Assert the changed value/order on the receiving editor before that editor saves. Settling user A does not settle user B. |
| Save and remount | Assert the destination URL and the required saved field/block. An unchanged update URL or a connected outer LiveView alone does not prove that the editor has remounted. |

For replacement media, an old visible image can satisfy a visibility assertion.
Capture its identity or source first and assert the new identity/source, plus
readiness where the next action requires decoded pixels. For removal, first
establish that the same locator finds the item being removed.

Some tests deliberately observe an interval to prove nothing happens, such as
the removed polling regression in `pages/draft-media.spec.js`. Preserve those
observation windows and deliberate latency injection. Document the behavior and
timer involved. Do not replace a sleep with another elapsed-time loop and call
it event-driven. If no reliable completion signal exists, document that limit
and investigate a suitable observable signal instead of deleting the wait.

Use accessible roles/labels for controls and the intended locale. Stable test IDs
are useful contracts; scoped structural selectors are appropriate for canvas,
layout and repeated block assertions. Position-based selection can be the actual
claim in ordering tests. Do not rewrite working locators merely to satisfy a
blanket selector rule.

## Preserve isolation and the real transport

- Import `test` from [setupAuth.js](../../../e2e/playwright/test-support/setupAuth.js).
  It binds browser requests to a per-test SQL sandbox through the user-agent
  (`sandboxUserAgent`); `page` is logged in. A login flow or anonymous visitor
  builds its own context with `browser.newContext({ baseURL, userAgent: sandboxUserAgent })`
  and closes it. Use `page.request` for fixture requests that must share the
  sandbox; a separate request context or `fetch` sends `sandboxUserAgent` as its
  `user-agent` explicitly.
- Keep authentication per test. The login endpoint creates a database session
  token inside the sandbox; reusing a global `storageState` does not preserve the
  token after rollback. `secondUserPage` supplies another identity in the same
  test sandbox for collaboration tests.
- Keep one worker per Phoenix server. SQL rollback does not isolate PubSub,
  caches, edit-session processes or the filesystem. Parallelize with the isolated
  shard runner from AGENTS.md, not `--workers=4` against one server.
- Check fixture responses before depending on their result. Close browser
  contexts before releasing their sandbox, including failure paths. Preserve
  test-owned cleanup rather than masking a leak with a retry.
- Control external integrations at their actual boundary. `page.route` handles
  browser HTTP requests, not Elixir's outbound requests or LiveView events over
  an existing WebSocket. Reuse the E2E backend providers. For transport faults,
  use the existing socket/latency helpers and assert recovery in the UI.

Read the [upload skill](../brando-uploads/SKILL.md),
[block skill](../brando-blocks/SKILL.md) or
[preview skill](../brando-live-preview/SKILL.md) if diagnosis reaches those
application contracts.

## Verify reliability and saved time

Measure the unchanged targeted test before optimizing, then compare equivalent
runs with the same fixture, browser and worker count. For example, from `e2e/`:

```sh
source .envrc
./test_e2e.sh --reset tests/blocks/block-image-editor.spec.js --retries=0 --repeat-each=5
```

Use `--grep` to keep repetitions on the relevant case while troubleshooting.
For a claimed regression, demonstrate that the original failure or a controlled
delay/broken behavior makes the assertion fail for the expected reason. Merely
inverting an expectation does not prove that it detects the application defect.
Keep intentional delays that exercise slow delivery distinct from readiness waits.

[timings.jsonl](../../../e2e/playwright/test-support/timingReporter.js) records
each attempt, including retries. Compare per-test durations and first-attempt
results; report GitHub job reruns separately. A static sum of sleeps is not a
measured saving: helper calls and loops multiply it, and shards overlap.
After targeted validation, run the full suite required by AGENTS.md. If it finds
a failure, return to that specific test before rerunning the suite.

The upstream [Playwright core](https://github.com/hzijad/playwright-agent-skills/blob/main/skills/playwright-core/SKILL.md)
and [debugging](https://github.com/hzijad/playwright-agent-skills/blob/main/skills/playwright-debugging/SKILL.md)
guides inform this workflow. Brando's sandbox, transport and timer contracts take
precedence over their generic auth reuse, worker-count and no-sleep examples.
