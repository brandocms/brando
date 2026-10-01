Block editor baseline — 2026-10-01

Fresh measurements for #2813, taken on `main` at `5ea18fc77` after the
2026-09-27 preview and deferred-TipTap work. Compare against
`block-editor-client-side-2026-09-13.md`. Private e2e instance
(`BRANDO_E2E_INSTANCE=claude_bench`), freshly reset, `e2e_seeds_large.exs`
re-run before each pass, admin bundle rebuilt from the same commit. The machine
was shared with other work, so wall-clock and round-trip numbers carry tens of
milliseconds of noise; byte, frame and render counts do not.

```
cd e2e && source .envrc
MIX_ENV=e2e mix run priv/repo/e2e_seeds_large.exs
cd playwright
pnpm playwright test --config bench/playwright.bench.config.js \
  bench/block-editor.spec.js bench/insert-breakdown.spec.js bench/tree-triggers.spec.js
pnpm playwright test --config bench/playwright.bench.config.js bench/interactions.spec.js
```

`bench/interactions.spec.js` is new. It replaces the throwaway spec behind the
keystroke, collapse and config rows of the September audit, and adds mount to
main-thread idle, preview open, preview bursts, copy, outline and draft capture.

## Round trips were over-counted

The September round trips ran from the first frame sent to the last frame
received in the settle window. Presence (`block_focused`/`block_blurred`) and
draft-capture traffic share the socket and land in that window. The new spec
matches replies by ref and ignores that traffic. `tree-triggers.spec.js` still
uses the old method; its copy "server=509 ms" is the same artefact.

Confirmed for config open at 115 blocks: eprof shows 5 ms of CPU in the
LiveView process, Ecto telemetry shows zero queries, and the frame timeline
shows the reply 4 ms after the click. The 618 ms in #2813 was a `block_focused`
event 600 ms later.

## Results

| | 40 roots | 115 roots | 2026-09-13 (40 / 115) |
|---|---|---|---|
| Mount payload | 2.04 MB | 5.49 MB | 1.92 / 5.19 MB |
| Mount, block-editor.spec wall (incl. 2.5 s fixed wait) | 3.2 s | 3.9 s | 4.8 / 15.9 s |
| Mount, navigation → editor ready | 0.63 s | 1.32 s | – |
| Mount, main thread (longest task) | 408 ms (308) | 865 ms (741) | – |
| DOM nodes after mount | 9,834 | 26,125 | – / ~21,000 |
| Keystroke diff in / out | 13.2 / 4.6 KB | 13.2 / 4.6 KB | 12.2 / 4.5 KB |
| Keystroke round trip, preview closed / open | 8 / 15 ms | 15 / 18 ms | 9 / 40, 19 / 135 ms |
| Insert, 3 clicks wall (main thread) | 0.51 s (52 ms) | 0.88 s (193 ms) | 0.74 s (252) / 1.8 s (637) |
| Collapse: icon flips / round trip / main thread | 49 ms / 19 ms / 0 | 85 ms / 27 ms / 0 | – / 323–441 ms main |
| Config open round trip, bytes | 16 ms, 42 KB | 5 ms, 30 KB | 2 / 618 ms (artefact) |
| Copy round trip, bytes | 11 ms, 0.3 KB | 7 ms, 1 KB | – / 719 ms (artefact) |
| Outline round trip, bytes | 15 ms, 17 KB | 29 ms, 45 KB | – / 218 ms, 45 KB |
| Draft capture upload | 117 KB | 337 KB | 117 / 335 KB |
| Save frame | 406 KB | 1.10 MB (134 frames) | 380 KB / 1.0 MB |
| Preview open round trip | 0.77 s | 1.60 s | – |
| 5 title keystrokes, preview open | 6 full renders, 170 KB | 6 full renders, 253 KB, 386 ms main | – |
| 5 block keystrokes, preview open | 5 `update_block` | 5 `update_block` | – |

Nested entry (40 × 3 levels): mount 1.94 MB, edit 3.5 KB, save 263 KB.

## What changed and what it means for #2813

- **Mount got about four times faster** on the same metric, very likely from
  deferred TipTap mounting (e6605e82d). Collapse and insert lost their
  main-thread cost the same way. The payload still grows: +6 % since
  September, +25 % over the August budgets.
- **Collapse already feels instant** (50–85 ms to the icon). Optimistic UI
  would save tens of milliseconds; the 13 KB diff per click remains.
- **The two "unexplained" numbers in item 6 were measurement artefacts.**
  Config open, copy and outline are all under 30 ms on the server.
- **Insert's picker click is a 9–15 ms round trip.** A client-side picker
  would save little at these sizes.
- **Save frames are 1.1 MB at 115 roots against a 75 KB budget**, one frame per
  block. Every save budget fails (flat-5 83 KB vs 60 KB, nested 263 KB vs
  235 KB), but `assertBudget` stops at the mount failure, so this was never
  reported. The post-save `replace_form` re-seed of every root is the likely
  source; unverified.
- **Live preview:**
  - Every entry-field keystroke triggers a full render and a 34 KB
    whole-document broadcast. 350 ms spacing is not merged by the 25 ms
    coalescing window.
  - Opening the preview sends one diff frame per block, about 5 ms apart:
    `enable_live_preview` fans out as a `send_update` per block, each handled
    as its own message.
- **Entry-field fan-out to consuming blocks** is 321 KB over 118 frames for one
  title keystroke on `/bench-entry-consumers`; unread fields are 9 KB.
- **Draft capture** is unchanged at 117 / 337 KB per capture.
