# LiveView audit fixes

All nine findings in [AUDIT.md](AUDIT.md) have been implemented. The changes
retain the block owner's form/ops contract and the upload selection guards.

| Finding | Implemented change |
| --- | --- |
| F1 | RenderVar derives media FKs and `value_id` from the current parent var form on ordinary updates, including replacement and clearing. |
| F2 | Picture/video refs reconcile media when the parent ref UID or FK changes. Matching processed media and pending local picker state survive unrelated parent updates. The shared resolver rejects stale/unloaded associations. Local video cover IDs remain local state. |
| F3 | Presence modal rows use ordinary assigned lists. Avatar streams keep their original DOM IDs. Moving online/offline removes the previous row. |
| F4 | Date and datetime hooks read a tracked value outside the ignored subtree and update Flatpickr without emitting a user edit. Unchanged server values preserve pending local input. |
| F5 | CodeEditor reconciles server values through a marked CodeMirror transaction, preserves pending textarea values, and destroys its actual `view`. The value attribute carries plain source: Phoenix's textarea normalization adds a newline and must only be used for textarea contents. |
| F6 | Gallery modal, configuration component, configuration input, and row-menu IDs include the owning gallery/form identity. Two fields can configure the same asset and row index independently. |
| F7 | FileBrowser and collection wrappers pass their existing tracking maps through direct internal function calls. Optional compiled-module state uses a named assign. |
| F8 | Select/MultiSelect cache against expanded option specifications and declared `options_depends_on` form fields. Opening/explicit refresh also updates labels and invalid selections. Page parent options declare their ID/language dependencies. Parent-derived settings and selected structs refresh without resetting local open state. |
| F9 | Identifier results/schema choices/counts refresh when schema, language, status, or layout filters change. Valid local schema tabs, including “all”, are retained. |

## Additional follow-ups

- Entries now follows parent association replacements/removal and language/source
  filter changes, including FKs whose identifier associations are not loaded.
- Shared-library rows, video duration and gallery thumbnails use explicit
  component dependencies instead of local HEEx calculation bindings.
- Color vars resolve palette colors at the component update boundary using the
  existing invalidated palette cache. Standalone color inputs use the same cache.
- Footnote definitions are resolved once per rendered block from the current
  module cache, then passed to each ref.
- Missing-block diagnostics, generated layouts/dashboard and their E2E examples
  preserve tracking. Repository guidance now distinguishes nil IDs (an error)
  from changing valid IDs, and explains zero-dependency HEEx expressions.

## Validation

The focused regressions are in:

- `test/brando_admin/components/change_tracking_render_test.exs`
- `test/brando_admin/components/form/input/change_tracking_test.exs`
- `test/brando_admin/components/form/input/identifier_change_tracking_test.exs`
- `e2e/e2e/playwright/tests/change-tracking.spec.js`

The E2E-only widget fixture is routed under the existing authenticated admin
routes and is enabled only with the SQL sandbox configuration.

Validation results:

- The complete admin component test directory, plus shared-library LiveView and
  presence tests: **334 passed** (330 tests and four doctests).
- Five targeted Chromium E2E cases passed: widget replacement/clear without edit
  echo, pending edits and widget destruction, picture upload/insert/save/reload,
  media-var edits/save/reload, and video selection/insert/save/reload.
- The E2E consumer asset build (`source .envrc` then `pnpm --dir assets/backend build`)
  passed. Vite reports its existing large-chunk advisory. No standalone root
  asset build was used.
- All 603 current HEEx templates across 235 source/support files passed through
  Phoenix LiveView 1.2.11's compiler. The three changed generator templates also
  passed EEx expansion and HEEx compilation.
- Four additional Phoenix engine-semantics probes passed.
- Formatting and whitespace checks passed on the changed Elixir sources.

The full E2E suite was not run. Browser tests used this worktree's isolated E2E
database, including a reset and migration rollback/forward check during setup.

The original [RESULTS.txt](RESULTS.txt) and synthetic
[browser-probe.cjs](browser-probe.cjs) describe the pre-fix audit evidence;
the browser probe deliberately demonstrates broken markup independently of the
application. [reproduce.exs](reproduce.exs) now retains only the four Phoenix
engine-semantics checks. Application regressions use the actual compiled modules,
not extracted source functions.
