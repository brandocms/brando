# Elixir Review — Phase 9 (commits HEAD~5..HEAD, `next`)

## Summary
- **Status**: ✅ Approved
- **Issues Found**: 3 (0 Blocker, 1 Warning, 2 Suggestions)

No PERSISTENT findings from Phase 8 — that shape (a comment/CHANGELOG claim not
matching the code) was checked deliberately here and, unusually, holds up: the
"markup only" claim in `video_drawer.ex`'s moduledoc and the CHANGELOG entry is
corroborated by independent evidence (no stray `Form.video_drawer` callers,
call site at `form.ex:2069` passes exactly the seven assigns the module reads,
Mux/Bunny/Cloudflare raise messages are consistent in shape and exception
type). This is the good outcome of that check, not an unchecked pass.

## Warnings

1. **`lib/brando/videos/uploaders/cloudflare.ex:272-282`** — the comment above
   the credential-raise reads as a changelog/commit narrative embedded in code
   ("recorded six times across the form audit before being decided rather than
   deferred again"). Per the iron law, comments should carry durable
   invariants a future reader needs (the `present?/1` vs. truthiness
   difference from Mux/Bunny is exactly that, and belongs), not the audit
   process history — that's already in `CHANGELOG.md` and the commit message,
   so it's duplicated here and will rot when nobody reads the audit docs it
   references. Trim to the invariant; drop the "recorded six times" framing.

## Suggestions

1. **`lib/brando_admin/components/form/video_drawer.ex`** — no `# prop`
   comments documenting the assigns it expects (`video_changeset`, `myself`,
   `schema`, `edit_video`, `processing`, `active_video_tab`, `video_context`),
   unlike the two sibling modules it explicitly follows
   (`meta_drawer.ex`, `scheduled_publishing_drawer.ex` both list `# prop
   name, :type, required:/default:`). Given the moduledoc is otherwise the
   most detailed of the three, the omission of that one convention stands out.

2. **`lib/brando_admin/components/form/video_drawer.ex`** — `processing` is
   passed in at the call site (`form.ex:2074`) but never read anywhere in the
   module. Not a regression (it was presumably equally unused before the
   move, since the moduledoc's "verified by diffing" claim covers the moved
   body) but now that the module is isolated it's a visible dead prop worth
   dropping from the call site, or wiring up if it was meant to disable the
   drawer's submit while a save is in flight.

## Notes (not findings)

- **Mutual alias coupling**: `VideoDrawer` aliases `Form` and calls
  `Form.input/1` twice (select inputs); `Form` aliases and calls
  `VideoDrawer.render/1`. This is a real mutual compile-time dependency
  between the two modules, not just a cosmetic alias — the extraction moves
  markup out but doesn't reduce coupling to `Form`'s `input/1`, which is
  still the 6211-line module. Worth naming for whoever attempts the
  `ImageDrawer`/`FileDrawer`/`Chrome` extractions next, since they'll hit the
  same shape if they also call back into `Form.input/1`.
- Pre-existing, not re-analyzed: `form.ex` at large (6211 lines) — scope was
  limited to the diff per instructions.
