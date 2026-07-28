# Scratchpad — block editor architecture decision

## How the numbers were obtained

Started the e2e app manually (`MIX_ENV=e2e PORT=4444 mix phx.server`), then ran throwaway
Playwright specs that attach to `page.on('websocket')` and record every `framesent`/`framereceived`
payload length, filtering out heartbeats. The specs used the normal `setupAuth` fixture so they got
a per-test SQL sandbox. Working harness preserved as `bench-payload.spec.js.reference`.

## Dead ends

- **`evalLV` in `e2e/e2e/playwright/utils.js` is unusable.** It pushes a `sandbox:eval` event, but
  no handler for that event exists anywhere in `lib/` or `e2e/lib/`. It looks copied from
  LiveView's own test suite. This is why server-side memory/assigns measurement was dropped from
  the benchmark and became a Phase 0 task.
- **Saving from a manually started e2e server hangs.** Both the mount-cost benchmark and the
  rich-text benchmark timed out at 10 min on the save step. Matches a previously recorded gotcha
  about sandbox ownership timeouts on manual `MIX_ENV=e2e` servers. Not investigated further —
  turned into a Phase 0 task since the mount measurement depends on it.
- **`.claude/audit/` is gone.** The July 2026 refactor commits reference
  `.claude/audit/reports/`, `.claude/audit/summaries/block-editor-architecture.md` and
  `.claude/audit/bench/bench_live_preview.exs`. All those directories are now empty, so the earlier
  scores (perf 38/100) and the live-preview bench could not be re-read. Everything here was
  re-derived from code, git history and fresh instrumentation.

## Phase 1 notes

- **Two latent breakages found while wiring up verification, both fixed.**
  (a) `bench/playwright.bench.config.js` had `webServer.cwd: '../../'`, which Playwright resolves
  against the *config file's* directory — that lands in `e2e/e2e`, which has no `mix.exs`. It never
  surfaced because `reuseExistingServer: true` skips the spawn whenever a server is already up, and
  Phase 0 always ran against a manually started one. Now `'../../../'`.
  (b) `test_e2e.sh --reset` runs `mix compile --force --warnings-as-errors`, and three e2e project
  HTML modules did `use Phoenix.Component` on top of `use BrandoWeb, :html` (which already does it),
  producing a redundant `__phoenix_component_verify__/1` clause. That gate was failing before any
  Phase 1 edit.
- To run the bench you must `source .envrc` in `e2e/` *in the same shell* as the Playwright
  invocation — the spawned `mix phx.server` inherits the env, and without `BRANDO_SECRET_KEY_BASE`
  every LiveView mount 500s with a `secret_key_base` error that looks nothing like a config problem.
- **DEAD END: reducing a closed config surface's vars to identity-only hidden inputs.** It reads
  like the obvious saving and `carried_var/1` already does it for `:hidden` vars, but
  `cast_assoc` matches params to records **by primary key**, so an unsaved var has nothing to
  match on and Ecto rebuilds it from the identity params alone — `key`, `placement` and `value`
  all come back nil. Blocks are created with unsaved vars, so this is the normal path, not an
  edge case. Symptom to recognise: `var_forms/1` returning `{nil, :content, :full, n}` for every
  var past the first. Keep the real inputs, hide the container.
- `.modal.visible` in `Modal.css` forces `display: flex !important`, which is why a server-gated
  modal needs no JS to appear — but also why `hide_modal`'s inline `display:none` could never win
  against it. Server-gated modals must close by dropping the assign, not by a JS hide.
- `Content.modal`'s `assign_new(:close, ...)` and its sibling `assign_new`s are **dead**: every one
  of those keys is a declared `attr` with a default, so the key is always present and `assign_new`
  never fires. Consequence today: escape-key and backdrop-click do nothing on any modal that
  doesn't pass `close` explicitly. Left alone — it is shared by the whole admin — but worth a
  separate cleanup.
- **`liveSocket.execJS(el, ops)` is the safe way to move a JS command client-side.** It dispatches
  into LiveView's own `JS.exec`, so `exec_show`/`exec_hide`/`exec_toggle` still route `display`
  through `DOM.putSticky` (`deps/phoenix_live_view/assets/js/phoenix_live_view/js.js:414,448,473,484`).
  Hand-rolling the class/style mutations instead would have been wiped by the next morphdom pass.

- **The bench fixtures could never save.** `e2e_seeds_large.exs` created its Page rows without
  `template`, which the Page changeset requires, so `update_with_changeset` failed validation on
  every bench save. The benchmark still printed a save latency, because it times the websocket
  round trip and not the outcome — so the plan's "save 3 826 ms" baseline was the cost of an error
  response. Fixed. A real save at 115 blocks ships **1 081 KB** inbound, which makes it the largest
  frame in the editor and something no phase of this plan has looked at.
- Any spec that asserts on a *latency* rather than an outcome can hide a failure like this. Assert
  the effect too.
- **Bisect payload questions, don't reason about them.** The save frame looked like an obvious
  `replace_form` problem — the cascade re-assigns `:form` on all 115 roots and the code even
  documents itself that way. Gating the cascade changed the frame by 0 bytes. Nulling `@entry`
  changed it by 98%. Two env-gated one-line experiments settled in minutes what an afternoon of
  reading would have got wrong.
- **A form field's `.value` is the *param* value once a validate has run**, not the struct value.
  An id rendered as `value={@var[:id].value}` when nil emits `value=""`, and that `""` comes back
  as the field value on the next render. Any "is this record persisted?" check on the form side
  has to treat blank as unsaved — `is_nil/1` alone silently stops matching after the first
  keystroke.

## Things worth knowing that didn't fit the assessment

- `assets/vite.config.js` declares entry `admin: 'src/main.js'`, but the package main is
  `src/index.js` and **`src/main.js` does not exist**. Consumers compile Brando's JS from source
  through their own Vite, so this stale input never bites — but it is misleading.
- Version skew between Brando and consumers is live: root `assets` pins Vite 8 /
  vite-plugin-svelte 7 / Svelte 5.55; `e2e/assets/backend` pins Vite 6 / vite-plugin-svelte 5 /
  Svelte 5.25. Relevant if Phase 4 adds islands that use newer Svelte features.
- `prototypes/block-editor-variants/` (untracked, 2026-07-26) holds three static HTML/CSS design
  studies for the block editor — canvas-inspector, flow-cards, slot-composer. They are pure design
  exploration, no Svelte, no framework. Worth noting because they imply a UX redesign may be
  coming, and a redesign is a much better reason to reach for a component framework than the
  performance argument is.
- The first edit after a block mounts costs ~30 KB; steady-state edits cost ~23 KB. Something
  extra is sent once per block per session.
- Live preview open adds only a 354-byte targeted frame per edit. The earlier "won't build
  incremental preview diffing" decision holds up.

## Rejected framings

- **"LiveView is bad at editors."** Not supported by the measurement. The per-edit cost is O(1) in
  block count and the constant is three-quarters removable boilerplate. The real defect history
  (~67 % LiveView-architecture-induced) is about *dual state ownership*, which was removed in July,
  not about LiveView per se.
- **"Move state to the client to offload changeset validation."** There is no content validation in
  the block edit path — zero `validate_required` calls in `block.ex`/`var.ex`/`ref.ex`. Nothing to
  offload.
- **"It's a small rewrite because Svelte is already there."** Svelte being wired up makes *islands*
  cheap. It does nothing about the Liquid editor-layout parser, HEEx runtime compilation,
  Plug-based live preview, the upload delivery chain, the collaboration op-sync, or the fact that
  the block editor has no authorization layer at all today.
