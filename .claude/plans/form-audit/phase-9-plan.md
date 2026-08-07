# Phase 9 — Close the audit's bookkeeping, take the deferred decision, start the extraction

**Source:** `.claude/plans/form-audit/reviews/phase-8-review.md` (all findings fixed in-session)
plus the twelve unchecked boxes still standing in `plan.md`
**Slug:** `form-audit` · **Depth:** standard · **Created:** 2026-08-07

Own file, following the Phase 5–8 precedent.

No research agents. The inputs are `plan.md`'s own annotations, which are
detailed enough to classify without re-reading the code they describe — and
where they are not, 9A says so rather than guessing.

---

## Where the audit actually stands

Phase 8 shipped and its review is closed: 2 BLOCKERs, 3 WARNINGs, 5 SUGGESTIONs,
all fixed and measured the same day (`reviews/phase-8-review.md`, retro in
`scratchpad.md`). Phases 0–8 are otherwise complete.

What is left is **not twelve tasks.** `plan.md` carries twelve `- [ ]` boxes,
and reading them is the single most misleading thing a new reader can do to
themselves tomorrow. Classified:

Located by **finding**, not by line — 9A moved every one of them, which is the
habit Phase 8A retired.

| Box | Finding | What it actually is |
|---|---|---|
| E2E: kill LV, assert pick survives | **B1** |  **Resolved by other means.** Phase 4's status note says so explicitly: `Brando.LiveCase` is what these needed |
| E2E: conditional/looped ref regression | **B5** |  **Resolved by other means.** Same note; covered at changeset + component level |
| E2E: root block children survive kill | **C1** |  **Resolved by other means.** Same note |
| Cross-entry snapshot leak | **C4** |  **Open, unconfirmed.** Static read says it needs `push_patch` within one LiveView; recorded as unconfirmed, not absent |
| `deliver_topic` stable across remount | **D2** |  **Built, then reverted** (`6da10b844`). Verified correct in-browser, still broke `block-multiuser-sync.spec.js:245` |
| Path helpers — collapse the 3× | **D-dup** |  **Rejected as written**, and the finding's "3×" is really 2×. Real work behind it is config-resolution unification |
| `image_picker`/`video_picker` — bound the query | **E** |  **Rejected as written.** Needs the folder tree to stop being derived from entries — a design change |
| `form/tab.ex` `:if` → class toggle | **F** |  **Attempted, then reverted.** Finding real, fix is not a line edit; causation established both ways |
| `Form.VideoDrawer` extraction | **G** |  **Open, real work** |
| `Form.ImageDrawer`/`FileDrawer` extraction | **G** |  **Open, real work** |
| `Form.Chrome` extraction | **G** |  **Open, real work** |
| Leave gallery/entry-relation in place | **G** |  **A decision, not a task.** It should never have been a checkbox |

So: **three genuinely open pieces of work** (the extraction), **one open
question** (`:418`), **two documented dead ends**, **two rejected-as-written
findings**, **three resolved-by-other-means**, and **one decision miscast as a
task**.

Nine of twelve boxes will never be ticked, and every one of them already carries
the annotation saying why. The defect is that the checkbox and the annotation
disagree, and the checkbox is what a reader sees first.

---

## Decisions needed

**1. The video-uploader credential disagreement — decide, or stop recording it.**
**→ CLOSED: (a), all three raise. Shipped `08c371da2`.**
Phase 8's plan committed to this in writing: *"Six recordings is enough evidence
that it will not arrive via a finding — if it is to be fixed, it needs to be
chosen deliberately, and Phase 9 is the place to either do that or stop
recording it."*

The disagreement, re-measured today: Mux raises (`mux.ex:545`), Bunny raises
(`bunny.ex:403`), Cloudflare returns `{:error, :not_configured}`
(`cloudflare.ex:273`). A caller cannot handle all three with one branch.

**ANSWERED 2026-08-07: (a).** Kept below as the record of what was weighed, per
the audit's practice of amending rather than replacing. Every option was a
public behaviour change on a library:

* **(a) All three raise.** Missing credentials are a deploy-time config error,
  not a runtime condition. Simplest contract; breaks any consumer currently
  matching Cloudflare's tuple.
* **(b) All three return `{:error, :not_configured}`.** Callers branch instead of
  rescuing. Breaks consumers relying on the raise to fail loudly at boot.
* **(c) Leave it, delete the recording.** Defensible — no finding has ever asked
  for it in nine phases — but then it stops being tracked, which is the point of
  deciding.

No option was free, (a) and (b) were both breaking, and the audit had spent six
recordings not choosing. **(a) was chosen and shipped in `08c371da2`** — see
Phase 9B below, and the retro in `scratchpad.md`. What made it the cheap
direction only became clear during implementation: it aligns Cloudflare with
behaviour `Bunny.delete_remote/1` already had on the same path, and
`{:error, :not_configured}` turned out to have one producer and no consumer.

**2. Extraction scope.** `form.ex` is **6565 lines** today, not the 6257
`plan.md` says — it grew 308 lines during the audit, which is its own small
argument for doing this. Three extractions are listed. They are not equal risk,
and 9C proposes doing **one** and measuring, rather than all three.

---

## Phase 9A — Make `plan.md` say what it means `[docs]` — **DONE 2026-08-07**

Cheap, and it is what makes tomorrow legible. No code. Done ahead of the rest of
Phase 9, so that a cold read of `plan.md` tomorrow starts from the truth.

- [x] **9A-1 — retire the nine boxes that are not tasks.** — done 2026-08-07: twelve `- [ ]` boxes are now three. Nine carry `[RESOLVED ELSEWHERE]` / `[REVERTED]` / `[REJECTED AS WRITTEN]` / `[DECISION, not a task]` / `[OPEN — UNCONFIRMED]`, every annotation kept verbatim. Convert each to a
      status marker that matches its own annotation: `RESOLVED ELSEWHERE`
      (`:144`, `:244`, `:363`), `REVERTED` (`:609`, `:997`), `REJECTED AS
      WRITTEN` (`:873`, `:945`), `DECISION` (`:1032`). Keep every word of the
      existing annotations — they are the evidence, and Phase 8's B1-record
      precedent is that records are amended, never deleted.
      **Do not** silently tick them. A ticked box claims work happened.

- [x] **9A-2 — carry Phase 4's note up to the three boxes it covers.** — done: each of the three now says "see Phase 4's status block" inline, and names what the harness does that the E2E spec does not (kills the process rather than disconnecting cooperatively). The
      sentence explaining that `:144`/`:244`/`:363` are addressed by the
      harness's existence lives only in Phase 4's status block, ~700 lines from
      any of them. One line at each site pointing to it.

- [x] **9A-3 — correct `form.ex`'s line count.** — done: heading reads **6565 lines**, measured 2026-08-07, with the old figure kept. The three extraction items are additionally marked **ranges stale** — the file grew 308 lines after they were written. section **G**'s heading said 6257;
      measured 6565. Fix the heading and note that the number is measured, with
      its date — Phase 8's S-5 was the same class of stale figure and cost a
      review round.

- [x] **9A-4 — restate the audit's status at the top of `plan.md`.** — done: a `## START HERE` block above the executive summary, carrying the open-work table, where the knowledge lives, the measured baselines, the warm-build caveat, and the audit's recurring lesson. One block:
      Phases 0–8 complete, what genuinely remains (the extraction, `:418`), and
      the pointer to `scratchpad.md` for the lessons. A reader opening
      `plan.md` cold should not have to classify twelve checkboxes to find out
      three of them matter.

---

## Phase 9B — The credential disagreement `[elixir]` — **DONE 2026-08-07**

**Decision 1 answered: (a) all three raise.** Taken by the user; implemented and
measured the same session. Seven phases of recording, closed.

- [x] **(a) — unify the three, one contract.** `cloudflare.ex`'s `api_request/4`
      raises instead of returning `{:error, :not_configured}`, with a message in
      the same shape as Mux's and Bunny's. `{:error, :not_configured}` occurred
      exactly once in `lib/` and nothing asserted it, so no call site needed
      rewriting — `delete_remote/1`'s `{:error, reason}` clause still covers the
      HTTP failures it was really there for.
- [x] **Checked before writing, not assumed.** Two paths reach a raising client:
      the admin form's `initiate_provider_upload/5` already rescues broadly
      (`form.ex`, "Provider clients raise rather than return") and turns any
      provider exception into an upload error, so the form is unaffected; and
      `delete_remote/1`, where **Bunny already raised on the same path**. So this
      aligns Cloudflare with existing behaviour rather than introducing a new
      failure mode — which is what made (a) the cheap direction.
- [x] **Tests — one per provider, plus the difference.** `provider_client_test.exs`,
      `describe "missing credentials"`: Mux, Bunny and Cloudflare each assert their
      own raise, and a fourth pins that Cloudflare alone rejects an **empty-string**
      credential (`present?/1` vs truthiness). That difference is about detecting
      the failure, not reporting it, so it was left in place and pinned rather than
      unified — recorded so it is not mistaken for an oversight.
      **RED, measured:** restoring the `{:error, :not_configured}` return —
      including the `if/else` structure it needs — reddens **exactly the two
      Cloudflare tests**; Mux and Bunny stay green. Run with the faithful
      mutation, not an approximation of it.
- [x] **CHANGELOG — under Breaking.** Names the old shape, the before/after
      branch, the two paths a consumer might notice (form uploads rescued;
      `delete_remote/1` not), why no shim is provided, and the empty-string
      difference left standing. `UPGRADE.md` defers to the CHANGELOG since 0.52.0,
      so there is no second place to write it.

---

## Phase 9C — Extract one drawer, and find out what extraction costs `[liveview]`

Section **G** lists three extractions "lowest risk first". The order is
`VideoDrawer` → `Image`/`FileDrawer` → `Chrome`. **Do the first one only**, then
decide with numbers instead of estimates.

Reason to be careful rather than fast: Phase 3's two attempted refactors in this
file (`:997`'s tab toggle, `:609`'s `deliver_topic`) were both **built,
verified, and reverted** after E2E caught what unit tests and in-browser checks
did not. That is a 2-for-2 record against changes to this component's structure.
The extraction is more mechanical than either — but the file's history says the
gate that matters is E2E, not `mix test`.

### Start here on a fresh context

Read, in order: this section → `plan.md`'s `## START HERE` → `scratchpad.md`'s
last two sections. Nothing else is needed to begin.

**The stale ranges are already re-measured (2026-08-07), so 9C does not inherit
them.** Section **G** said `handle_event:3549-4069`. That range is wrong in
*both* directions: it **misses** `save_video` (`:4137`) and
`save_video_authorized` (`:4144`), and it **swallows** unrelated file and image
handlers (`reset_file_field`, `validate_file`, `save_file`, `validate_image`,
`save_image`, `image_editor_save`). Extracting by it would have moved the wrong
code and left two clauses behind — the risk this plan flagged, confirmed by
measuring rather than by trusting the note. Cited by name below, per 8A.

**`update/2` clauses — the drawer's inbound messages:** `:update_edit_video`
(three clauses), `:open_video_drawer`, `:get_video_upload_url`,
`:video_upload_complete`, `:video_upload_error`.

**`handle_event/3` clauses:** `"reset_video_field"`, `"reset_video_thumbnail"`,
`"parse_video_url"`, `"extract_thumbnail"`, `"validate_video"` (2),
`"save_video"` (2), `"save_video_authorized"` (2).

**Check before moving it:** `"extract_thumbnail"` is the only name in that list
that does not say "video". Confirm it belongs to the video drawer and is not
shared with the image editor.

- [ ] **9C-1 — extract `Form.VideoDrawer`**, using the inventory above.
      Communicates via `send_update` already, so the seam is declared clean —
      **verify that claim before relying on it**, the same way Phase 8's SEC-1
      verified "no Bunny call follows a redirect" before changing transport.
- [ ] **9C-2 — E2E is the gate, and run it before believing the extraction.**
      `projects.spec.js:290` is the spec that caught `:997`; the video drawer is
      exactly its subject. Run the full suite, not that file alone.
      **RED:** state, before running, which spec would fail if the extraction
      dropped an event handler — then confirm it does by removing one.
- [ ] **9C-3 — record the cost.** Lines moved, wall-clock, whether E2E caught
      anything `mix test` did not. That number is what decides whether
      `ImageDrawer`/`FileDrawer` and `Chrome` happen in Phase 10 or not at all.

---

## Phase 9D — `:418`, or close it `[liveview]`

- [ ] **Decide whether the cross-entry snapshot leak is worth reproducing.**
      finding **C4** says the static read makes it hard to reach: the snapshot is
      written only by `disconnected()` and read only by `reconnected()`, so it
      needs the same hook element to survive an entry change — a `push_patch`
      within one LiveView, where entries use `push_navigate`.
      Either build that case and see, or mark it `UNCONFIRMED — closed` with the
      static argument as the reason. **What is not acceptable is a tenth phase
      that still says "recorded as unconfirmed"** — that is the same pattern the
      credential disagreement just spent six phases in.

---

## Verification

Baselines are Phase 8's **as measured on the fixed tree** (2026-08-07), not as
recorded before the review:

| Gate | Baseline | Phase 9 expectation |
|---|---|---|
| `mix test` | **1291 tests + 135 doctests, 0 failures** (Phase 8 shipped 1281; +1 `req` version pin, +5 CDN redaction tests, +4 provider credential tests) | ≥ baseline, 0 failures |
| `mix credo --strict` | 284 | ≤ 284 |
| `mix compile --warnings-as-errors` | clean | clean |
| `mix format --check-formatted` | clean | clean |
| Unit-suite output | 43 stdout / 27 non-dot / 0 stderr, **warm build** | ≤ baseline |
| E2E | 107 / 0, measured 2026-08-07 (three runs, one per round that touched `lib/`) | 107 / 0 after 9C |

**The output-noise figure is a warm-build number.** A `mix test` that also
recompiles adds two non-dot lines (`Compiling N files`, `Generated brando app`).
That artefact is what produced the 27-vs-32 disagreement in Phase 8's review;
it will recur, and re-running on a warm build is the whole fix.

9A and 9D are doc-only and have no RED. Saying so is the correct answer for
them. 9B and 9C both do.

---

## Sequencing

```
9A  Bookkeeping        ✔ DONE 2026-08-07  (a5dac0331)
9B  Credential         ✔ DONE 2026-08-07  (08c371da2, breaking)
      ↓
9C  Extraction        ◀ NEXT — 9C-1 → 9C-2 → 9C-3
9D  :418               decide, or close   (independent of 9C)
```

9A and 9B are closed and committed. **9C is the next step**, and 9D can be taken
in either order relative to it — they touch nothing in common.

---

## Risks

**What is this plan most likely to get wrong?** Underestimating 9C. Two
structural changes to `form.ex` have been built and reverted in this audit, both
after passing everything except E2E. The plan's "these already communicate via
`send_update`, so the seams are clean" is an *unverified claim written before
either revert* — 9C-1 treats it as a claim to check, and if it does not hold,
the honest outcome is a third revert recorded rather than an extraction forced
through.

**Where could this phase quietly grow?** 9B under option (a) or (b). "Unify
three providers" is one line each, and then it is a breaking change to a library,
which means a CHANGELOG entry, an UPGRADE note, and a decision about a shim —
the `key_available?/2` change took most of a phase for exactly that reason.

**What is being assumed without checking?** That section **G**'s line ranges
still locate the video drawer. They almost certainly do not — the file grew 308
lines after they were written, which is more than the audit's measured error
rate on citations needs. 9C-1 says to re-measure and cite function heads; the
risk is doing the extraction from the stale ranges instead.

---

## Traceability

| Item | Origin | Task | Phase |
|---|---|---|---|
| Nine non-task checkboxes | `plan.md` | 9A-1, 9A-2 | 9A |
| Stale `form.ex` line count | measured 2026-08-07 | 9A-3 | 9A |
| No status at top of `plan.md` | this plan | 9A-4 | 9A |
| Credential disagreement | Phases 4–8, six recordings | 9B | 9B |
| `Form.VideoDrawer` | **G** | 9C-1…9C-3 | 9C |
| `Form.ImageDrawer`/`FileDrawer` | **G** | **deferred to Phase 10, deliberately** — gated on 9C-3's number | — |
| `Form.Chrome` | **G** | **deferred to Phase 10, deliberately** — same gate | — |
| Cross-entry snapshot leak | **C4** | 9D | 9D |

Skipped: none. Deferred: two, both named above with the condition that ungates
them — which is the difference between this deferral and the credential one.
