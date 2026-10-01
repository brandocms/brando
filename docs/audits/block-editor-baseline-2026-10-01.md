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

## Follow-up: save re-seed and live preview (same day)

Measured with the same bench on `/bench-flat-115` unless noted.

| Metric | Baseline | After |
|---|---|---|
| Save frame, 115 / 40 / 5 roots | 1.10 MB (134 frames) / 406 / 83 KB | 76 KB (21 frames) / 66 / 62 KB |
| Save frame, nested | 263 KB | 161 KB |
| Preview open round trip | 1.65 s, 115 diff frames | 0.81 s, one 19.5 KB diff |
| 5 title keystrokes, preview open | 6 `update`s × 34 KB = 253 KB | 3 `update`s × 21 KB = 112 KB |

- **Save:** after a save each block field re-seeds only the roots it cannot
  prove already hold the saved row (`BlockField.holds_persisted?/2`). What
  remains in the frame is the three roots the bench edits or inserts.
- **Server time for a full preview render is about 10 ms** at 115 roots
  (materialize 1 ms, render 5–11 ms); 25 ms of the 35 ms between `validate`
  and the broadcast is the coalescing window. The 80 ms the browser sees
  after the `validate` reply is its own main thread applying that reply, not
  the server. Fixture modules are small, so real pages render slower and
  their documents are larger.
- **Preview renders are now at least 1 s apart.** The first change after a
  pause still renders within the 25 ms window; later ones render the latest
  state once the interval has passed (`Form.Preview`).
- **`update` broadcasts carry only `<main>`,** the only part the iframe
  morphs: 34 → 21 KB per update here.
- **Opening and closing the preview is one render.** The flag travels as
  attributes, Form → BlockField → blocks. The single diff is larger than the
  115 small frames were (19.5 vs ~8 KB), because BlockField re-sends every
  root's wrapper fields. Collection on open also waits 150 ms instead of
  500 ms, the same margin save uses.
- Still open: opening the preview triggers a 337 KB draft capture (item 8),
  and most of the remaining 0.8 s is the iframe loading the page.

## Follow-up: collapse, picker, draft capture, entry fan-out (same day)

| Metric (115 roots) | Baseline | After |
|---|---|---|
| Collapse, icon and block flip | after the validate reply | at once (e2e test holds server frames for 1.5 s) |
| Draft capture after the first | 337 KB up, ~145 ms of LiveView time | 4.5 KB up, root rebuild 0 ms |
| Entry-field fan-out, 115 consumers | 320 KB, 118 frames | 40 KB, 118 frames |
| Keystroke inside a block | 13.2 KB | 12.8 KB |

- **Collapse** flips its class and icon on the client (`uiCommands.js`, CSS
  off the checkbox); the validate still runs and its patch agrees.
  `e2e/playwright/test-support/latency.js` holds server frames so a test can
  assert what shows before the reply.
- **The picker already opens without a round trip.** `data-ui-modal-show`
  shows it client-side with the module list it last had; the round trip only
  re-filters that list and records where to insert, and LiveView processes the
  insert after it.
- **Draft capture:** the browser sends only block forms edited since the last
  save (all of them on the first capture after load or reconnect), and
  BlockField reuses a root's snapshot while its inputs are unchanged. The
  remaining ~35 ms per changed capture is writing the full draft row
  (option 3, on hold).
- **Entry fan-out:** each consuming block re-sent its whole form because of
  derived assigns in function components, the `inputs_for` `:let` slot and
  `<.form>` rebuilding its attributes. Now about 250 B per block. Mount fell
  from 5.50 to 4.80 MB in the e2e build, mostly HEEx debug annotations that
  production does not send.
- **Item 7, the keystroke diff, is the block's whole form.** Every input reads
  the one Phoenix form, so an edit anywhere re-sends the toolbar and every ref
  input. Vars avoid it by being their own components (~0.7 KB). Doing the same
  for refs is the fix; it is a larger change and not started.

## Follow-up: block variables and ref config (same day)

| Metric (115 roots) | Before | After |
|---|---|---|
| Server memory, open editor (settled GC) | 5.52 MB | 5.26 MB |
| Keystroke in a header block | 12.8 KB | 8.1 KB |
| Mount payload / DOM nodes | 4.80 MB / 26.7k | 4.32 MB / 23.6k |

- Each RenderVar's `on_change` closure held the vars template's whole
  assigns and changed every render; it now holds only the target.
- Closed ref config is carried as bare hidden inputs for header, text, map and
  SVG refs (`carried_config` on `Block.Render.block/1`). Picture, video, file
  and gallery still render their config slot hidden.
- Refs as their own components would not shrink a keystroke in a block's only
  ref, which is the fixture's case: the edited ref is what re-renders. Memory
  for it was estimated, not prototyped: about 5–20 KB per ref component.
