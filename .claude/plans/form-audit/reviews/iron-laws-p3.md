# Iron Law Violations Report — Phase 3 (form-audit)

**Scope note:** This agent has no Bash access and could not run `git diff HEAD~5`
directly. Scope was reconstructed from `.claude/plans/form-audit/plan.md` §"Phase 3 —
Efficiency, idioms, dead code" (E: performance, F: dead code/drift) plus the file
list the orchestrator supplied (`form.ex`, `block.ex`, `block_field.ex`,
`image_picker.ex`, `input/options.ex`, `input.ex`, `input/select.ex`,
`input/multi_select.ex`, `dsl.ex`, `blocks.ex`, `form/tab.ex`, `Form.css`,
legacy.ex deletion). Findings below are scoped to that set; anything outside it
was not audited.

## Summary
- Files reviewed: ~15 (form.ex, block_field.ex, image_picker.ex, input.ex,
  input/select.ex, input/multi_select.ex, input/options.ex, form/tab.ex,
  Form.css)
- Iron Laws checked: 12 of 26 (mount/DB, PubSub+connected?, assign_new lifecycle,
  raw(), String.to_atom, GenServer/Agent justification, inline styles [project
  rule], sticky-JS [project rule], constant-options-in-templates [project rule],
  comments-as-commit-messages, handle_event authorization, cross joins/float/Oban
  not applicable — no schema/migration/worker files in this diff)
- Violations found: 0 confirmed BLOCKER/WARNING; 1 SUGGESTION (pre-existing
  pattern, noted for completeness, not introduced by this diff)

No BLOCKER or WARNING violations found in the reviewed Phase 3 files.

## Suggestions

### [#11] Authorize in every handle_event — REVIEW
- **File**: `lib/brando_admin/components/image_picker.ex:169-186` (`delete_image_from_picker`),
  `:213-238` (`picker_move_to_folder`)
- **Code**: `Brando.Images.delete_images([image_id])` / `move_images_to_folder(ids, folder_id)`
  called directly off `handle_event` params with no visible per-event authorization check
- **Confidence**: REVIEW — this is the pre-existing convention across the entire
  `brando_admin` admin panel (auth is enforced at the router/plug boundary for all
  `/admin` routes, not per-event); not introduced or changed by Phase 3. Flagging
  for completeness only, not as a regression.
- **Fix**: none required unless the project's auth model changes; if per-action
  authorization (e.g. folder-scoped permissions) is ever needed, this is the choke
  point.

## Verified Clean (worth recording, since these were exactly the areas Phase 3 touched)

- `image_picker.ex` — `assign_config_target/1` correctly renamed from the old
  `assign_images/1`; no longer retains the image list in `socket.assigns`, list is
  streamed (`stream(socket, :visible_images, [])` at mount). No inline `style=`
  introduced.
- `block_field.ex:657-676` — PubSub `subscribe` and `request_blocks_sync/1` both
  correctly gated on `connected?(socket)`.
- `form.ex:1450-1481` — `assign_addon_statuses/1`/`assign_transformer_statuses/1`:
  `assign_new` used only for schema-derived, mount-stable facts; two exceptions
  (`has_meta?`, `has_alternates?`) correctly kept as plain `assign` since they
  depend on values that change after mount (satisfies Iron Law "never use
  `assign_new` for values refreshed every mount" — these are not refreshed, so
  `assign_new` is correct here, not a violation).
- `input.ex:285-296`, `input/select.ex`, `input/multi_select.ex` — `Options.expand/1`
  for `:languages`/`:admin_languages` tokens is computed in the function-component
  body *before* the `~H` template, not called inline inside HEEx markup — this is
  the correct pattern for function components (which re-run their whole body on
  every parent render regardless); does not violate the "constant options in
  templates" rule, which targets calls written directly inside `~H`.
- `assets/css/components/Form.css` — no `style=` attributes found; the dead
  `svg path:nth-of-type(2)` fill-override selector tied to the removed inline
  `<svg>` elements was removed, matching the plan's F-section note.
- No `String.to_atom(`, `use GenServer`/`use Agent`/`use Task`, or inline-issue-tag
  comments (`XX-1234`) found in the reviewed files.
- `form/tab.ex` — the video drawer Upload/External-URL panels remain gated on
  `:if` (the class-toggle refactor was attempted and reverted per the plan, with
  the reasoning recorded in a comment above `tab_content/1`); no orphaned dead
  code from the revert was found.

## Caveat

Without Bash/`git diff` access this review could not enumerate the exact 25
changed files or verify line-level diff hunks (+1138/-224). If any of the other
~10 files in that diff were not covered above (e.g. `dsl.ex`/`ComponentResolver`,
`blocks.ex` dead-code removal, `legacy.ex` deletion, `block.ex` container/fragment
scoping), they were not audited by this pass and should be spot-checked
separately, ideally by an agent with shell access to run `git diff HEAD~5 --stat`.
