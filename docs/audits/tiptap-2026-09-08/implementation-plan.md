# Tiptap implementation plan · 9 September 2026

Status: implemented on `codex/tiptap-editor-care`. See [implementation and verification](implementation.md) for delivered behavior, focused checks, screenshots and compatibility notes. The sequence below records the approved plan.

Baseline: fetched `origin/next`, verified it matched local `next`, then rebased successfully from `443943ad7` onto `c9c29c9f5`. Implementation now lives on `codex/tiptap-editor-care`. The original [audit](audit.md) and [diagnostic evidence](evidence.json) are preserved as historical observations against the earlier commit. This plan incorporates the footnote translations and module-definition DSL now on `next`; it does not claim that the original browser diagnostics were rerun after rebasing.

## Decisions and compatibility requirements

- **Keep HTML as the persisted content format.** No JSON migration, dual source of truth, or wholesale rewrite of existing documents.
- **Keep existing extension lists, styles, footnote options, and per-ref configuration.** Optional presets supplement the existing controls. They are authoring conveniences, not a replacement configuration system or a new inherited dependency.
- **Preserve readable anchors and existing fragment URLs.** Repair the current anchor representation first. The audit's proposed node migration is no longer the default plan.
- **Style keys stay inside the editor configuration.** Collision-safe extension names must not add opaque identifiers to the saved text or HTML. Existing class names remain unchanged, e.g. `<p class="lede">…</p>` and `<span class="small-caps">…</span>`.
- **Lists use one split control.** Outside a list, the main button creates bullets. The arrow offers bulleted and numbered lists. Inside a list, show its actual type; do not make the last chosen numbered type an unexpected default for the next paragraph. Alphabetic/Roman numbering is a separate optional extension, not implied by this first version.
- **Keep Tab / Shift-Tab for list nesting.** They already call `sinkListItem` / `liftListItem` in the installed Tiptap list extension. No permanent indent/outdent buttons. A contextual menu can expose the same commands for touch users; unavailable commands must not trap Tab.
- **Blockquote is explicit opt-in.** Exclude it from every shipped preset and the ordinary default toolbar. Preserve existing quotes when opening content. Keep standalone quote blocks as Brando's usual authoring workflow.
- **Expanded editing and reviewed AI suggestions are in scope.** Both must preserve the editor instance, selection, undo history, HTML mirror, and existing form/block ownership.
- **The approved mockup informed the compact block-type control.** Use `¶` / `H2` by default, with icon-only and full-label configuration available. Named styles expose their active state in the opened menu, without another permanent label beside the control.

## Delivery order and coverage of audit items 1–12

| Change | Audit coverage | Result | Depends on |
| --- | --- | --- | --- |
| A. Dependency coherence and fast regression harness | Prerequisite; groundwork for all items | One compatible ProseMirror runtime; reproducible editor diagnostics become maintained tests | — |
| B. Safe, compatible links and content references | 1, 5; entry-link follow-up | Shared URL policy, one link representation, reliable identifier URL propagation | A |
| C. Editor lifetime and footnote correctness | 2, 3, 4 | Targeted updates, preserved local history, cleanup, non-destructive footnote insertion | A |
| D. Configuration, presets, styles and paste | 6, 7, 11; part of 12 | Honest authoring controls, additive module-editor presets, preserved HTML semantics | A, B |
| E. Anchor repair | 8 | Existing readable IDs survive formatting, removal and reload | A, D's HTML fixtures |
| F. Toolbar, accessibility, link workspace and expanded mode | 9, 10; list and focus requests | Compact accessible controls, polished link editing, same-editor expanded mode | B, C, D, E |
| G. AI proposal workflow | AI request; completes replacement portion of 3 | Async generation, visually distinct proposal, Accept / Discard / Retry, single-step undo | C, D, F |
| H. Measured cleanup and release checks | 12; final coverage of all items | Remove dead code, fix color state, optimize proven costs, document compatibility | A–G |

These are reviewable change boundaries, not a requirement to wait until H for every useful fix. Ship B and C as soon as their focused checks pass; keep new UX features opt-in until their own checks pass.

## A. Establish a fast, realistic test foundation

Reconcile `assets/pnpm-lock.yaml`, direct ProseMirror dependencies and imports so the actual consumer resolves compatible packages without loading two model instances. Prefer the existing `@tiptap/pm` entry points where applicable. Confirm resolution through Yalc and the E2E application's Vite configuration. Do not treat a temporary alias or a passing standalone root asset build as the fix, and do not combine this with an unrelated major upgrade.

Use three inexpensive layers:

1. Extend the existing `node:test` pattern in `test/javascript/` for configuration resolution, collision-safe style keys, update routing, subscription cleanup and AI request/revision state. Keep pure modules importable without a browser.
2. Mount the real Svelte editor and LiveView hook in a small Vite fixture, exercised with the existing `@playwright/test` dependency. Reuse consumer resolution and styles; mock only the LiveView transport. Run without Phoenix, a database, seeding or per-test application login. Keep the fixture in a distinct configuration so these tests cannot accidentally start the full E2E stack. This follows Playwright's current [component test approach](https://playwright.dev/docs/test-components), using ordinary tests against a small page rather than a new experimental component framework.
3. Add focused ExUnit tests for server URL validation, identifier rewriting and owner invalidation, module configuration/DSL round-trips, and AI event ownership. Use the existing database sandbox only where the behavior genuinely depends on persistence.

The original `/tmp` audit harness is diagnostic material to replace with maintained fixtures; it is not the test installation. Include passing baseline cases as well as each reproduced failure. Run one shared dev server per browser-test invocation, isolate editor state per test, and avoid sleeps in favor of transaction/event assertions. Measure warm suite duration before setting a CI budget; aim for seconds for pure tests and tens of seconds for the focused editor suite, not an unverified timing promise.

Acceptance: typing `- ` and `1. ` works without Fragment errors; explicit quote configuration supports `> `; a second list item indents/outdents with Tab/Shift-Tab; pressing Tab where nesting cannot apply does not strand focus.

## B. Links, buttons and identifiers — items 1 and 5

Extend the maintained Link behavior with button appearance instead of allowing two overlapping anchor marks. Parse class tokens, preserve identifier metadata and supported extra classes, and serialize existing `class="action-button"` output. Retain command adapters while callers migrate. Appearance is an editor concern mapped to the existing class, not a new attribute that has to appear in HTML. Applying/changing/removing a link over partial selections must produce valid, non-nested anchors.

Define a shared URL contract for ordinary links, button links, paste/import and server-side rich-text validation. Cover HTTPS/HTTP, approved application schemes, relative paths, fragments, email and telephone links; reject executable schemes and ambiguous control-character forms. Trim input and deliberately normalize hostname-style input to HTTPS while preserving intentional relative links. Use one set of policy fixtures across client and server implementations. Reuse existing HTML parsing/sanitizing dependencies. Scope validation to rich-text input boundaries; do not silently apply a generic scrubber across unrelated raw HTML fields. Preserve approved classes, jump anchors, identifier metadata and footnotes.

**Entry links already exist.** The Content tab stores an identifier reference alongside the current href. Normal mutations update that URL and enqueue a cascade for references in blocks/vars. Link wording stays authored; renaming an entry should not rewrite editorial link text automatically.

Complete that contract for ordinary rich-text fields: make the rewrite independent of attribute order and escaping; identify changed owner entries; route them through their normal rendering/cache invalidation path. The current direct SQL field rewrite is not evidence that every owner is rerendered. Verify the entry's ordinary URL-change mutation, not just the separate helper whose name promises a rerender. Respect site/tenant scope, deleted or unavailable destinations, and supported local fragments. Preserve internal metadata in stored HTML and the existing public-output stripping behavior where used.

Acceptance: safe legacy links and buttons round-trip; unsafe URLs fail visibly without closing the dialog; no nested anchors; extra classes do not turn buttons into plain text; renamed URLs propagate to block refs and ordinary rich-text owners; reordered attributes, multiple links and escaped URLs work; link text remains unchanged.

Primary files: `assets/src/components/TipTap/extensions/Button/index.js`, `TipTap.svelte`, `lib/brando_admin/components/form/input/blocks/tiptap_link_dialog.ex`, `lib/brando/content/blocks.ex`, `lib/brando/content.ex`, `lib/brando/villain/villain.ex`, and `lib/brando/workers/entry_cascade.ex`.

## C. Preserve editing state — items 2, 3 and 4

Register hook event handlers once and unregister hooks/listeners on destruction. Keep the global registry bounded after mount/destroy cycles. Consolidate hidden-input synchronization so a command produces one document update rather than a second synthetic duplicate.

Replace rich-text uses of broad remount events with a targeted update carrying editor identity, source and enough version information to reject stale replies. Do not redesign every component's remount contract. Document these cases explicitly:

| Source | Required behavior |
| --- | --- |
| Local edit / normal save acknowledgement | Keep editor and history; ignore equivalent server echoes |
| Another field changes | Leave this editor untouched |
| Accepted AI proposal | One local, undoable transaction through the normal mirror |
| Genuine remote replacement | Respect existing ownership/defer rules; avoid echoing the replacement and prevent undo from reviving stale remote state |
| Draft restoration or switching entries | Deliberate replacement/history policy; never accidental loss caused by an unrelated update |
| Composition / open picker | Preserve or map the selection; defer unsafe replacement; do not apply a stale saved range |

The LiveView form/block remains the server owner; Tiptap owns its ignored DOM and current local editing state. Block updates must pass through `Block.assign_block_form/2` and its reducer op; existing `replace_form` remains the sanctioned parent handoff. Do not add a second autosave/gather protocol. The hidden HTML mirror must be current for immediate Save and recovery.

For footnotes, capture the selection end before opening the drawer, map it across allowed transactions and insert the reference there without replacing selected words. Reject a stale insertion target gracefully. Retain UID ownership and the translations added on `next`. Specify same-entry duplication and cross-entry paste: a marker cannot silently borrow a definition from another entry. Render missing-definition feedback without deleting the author's text.

Acceptance: unrelated patches retain selection/undo; same-value acknowledgements produce no loop; repeated remount/destroy cycles do not accumulate callbacks; canceled/stale picker responses do nothing; selected text survives footnote insertion; immediate Save captures the edit; recovery and remote replacement follow their existing state contracts.

## D. Additive configuration, named styles and semantic paste — items 6, 7 and 11

Create one capability registry consumed by controls, commands, shortcuts, input rules and paste policy. Retain enough schema support to read existing content: authoring restrictions must not delete old headings, styles, quotes or footnotes on the next edit. Specify allowed formatting of existing legacy structures separately from creating new ones. Preserve explicit configuration and distinguish missing configuration, legacy `all`, and an intentional empty selection. Keep `list` as a backward-compatible bullet-list key and add an explicit ordered-list capability. Resolve the ordinary default and legacy `all` through a documented capability set: blockquote creation is off unless explicitly selected, including its shortcut/input rule. Existing quote HTML still loads and survives edits. Keep the stored legacy option rather than rewriting every module on save. Document this correction to previously unrestricted keyboard behavior and test it alongside the user-requested additional list controls.

**Module editor interface:** extend the existing text-ref Extensions multiselect and Styles extras, rather than replacing them. Add an optional “Add preset…” control offering a small initial set such as Basic, Caption and Article. Show which capabilities will be added; applying it unions them into the explicit current selection. It does not remove existing capabilities, styles, footnote settings or content. The multiselect remains editable afterward, with a compact preview driven by the actual configuration. New refs may start from a preset deliberately; existing refs do not gain a preset automatically. Store the resolved explicit list in the existing field, so later preset changes cannot silently change existing modules. Remove the raw extension-value debug output.

Keep footnote settings and the current element/class/label/icon style editor, improve validation, and use stable component IDs. A module save already synchronizes all dependent blocks; test module-version classification, retained content, stale-editor behavior and the new definition DSL's read/write/import/export paths. A configuration helper must not become an implicit content migration. Support the same resolved options and styles on ordinary Blueprint rich-text fields; an optional convenience helper can produce an extension list without introducing a competing persisted profile field.

Style extension keys must use an injective encoding of the exact style identity, not punctuation replacement or a random key regenerated on every mount. Validate truly duplicate definitions. Renaming a display label must not change the CSS class or saved text. Display configured icons where provided. “Remove text formatting” clears visual inline formatting while retaining links, anchors and note references; “Reset paragraph style” removes configured block styles without unexpectedly changing alignment or structure. Name any separate alignment reset explicitly.

Paste transforms style-encoded bold/italic into supported semantic tags before removing foreign presentation. Preserve intentional link targets, lists, approved Brando classes and valid internal metadata. Use real sanitized fixtures from Brando, Word, Google Docs and web content. Keep native paste-as-plain-text. For unsupported tables/media, retain useful text and show a concise fallback indication where content would otherwise vanish. Do not insert media schema or a table editor as incidental scope.

Acceptance: existing refs/fields render unchanged under legacy settings; applying a preset adds features without removing manual choices; restrictive settings cannot create disallowed content via shortcuts/paste; existing supported legacy content survives a load/edit/save cycle; inline and block style clearing does what it says; `foo-bar`, `foo_bar` and case-distinct classes remain distinct with no new serialized style IDs; module UI and DSL round-trip the same resolved configuration.

Primary files: `TipTap.svelte`, `PasteCleaner/HTMLInputParser.js`, `lib/brando_admin/components/form/input.ex`, `lib/brando_admin/components/form/module_props/ref_block_form.ex`, `lib/brando/villain/blocks/text_block.ex`, and `lib/brando/content/definition/`.

## E. Repair anchors without sacrificing their HTML — item 8

Keep IDs such as `#getting-here`, including exact case/spelling of existing IDs. Keep the current `span[data-type="jump-anchor"]` representation as the initial compatibility target. First test whether mark ordering and split/inheritance rules can keep one outer anchor span across differently formatted text; fix caret removal by extending the anchor range. Test formatting, links, inline styles, Enter, cut/paste and undo, not just a plain-text example.

Use a small anchored editor panel for a readable ID, duplicate feedback, Copy link, Rename and Remove. Do not regenerate IDs when heading text changes. Only a deliberate rename changes an existing inbound URL. Check duplicates in the full entry editor where possible, including other blocks, and define deterministic paste behavior without silently renaming an existing destination.

If the current mark cannot represent all operations safely, pause that specific structural choice for a demonstrated HTML comparison. A node/atom migration is not pre-approved by this plan. A page outline or automatic heading-ID feature is separate future work.

Acceptance: formatting inside an anchor produces one destination ID; caret removal works; reload preserves readable IDs; pre-existing fragment URLs still resolve; copying content cannot silently introduce duplicate destinations; anchors survive visual-format clearing.

## F. Compact authoring UI, link workspace and expanded editing — items 9 and 10

Use the approved [admin design guide](../../admin-ui-design.md), shared `Content.modal` / `SelectIdentifier` workspace, and `ModalWorkspace.css`. Keep the restrained sage/blue surfaces, compact controls, section spacing and header/footer treatment from the earlier modal work. Validate with actual consumer fonts/styles before visual sign-off; the accompanying mockup is an interaction proposal, not an application screenshot.

Toolbar: compare the three block-type label treatments before settling the default. Use one paragraph/style dropdown, bold/italic, a split list button, Link, a restrained More menu, Undo/Redo and Expand. Keep uncommon controls configurable. Put blockquote only in explicitly enabled configurations. Supply truthful tooltips, mixed-selection states, command availability and active colors. Add useful empty-editor guidance; optional counts belong in expanded editing, not every small field.

Accessibility: connect the editable DOM to the field label, instructions and errors; set multiline/required/invalid state; expose pressed/expanded/disabled state; restore visible focus. Implement toolbar arrow-key navigation and a discoverable shortcut from the document. Menus, color selection and contextual link editing must work without a mouse. Preserve selections through toolbar and dialog focus. Make read-only/presence-lock state affect actual editing and keyboard commands, not only pointer CSS. Preserve translations and localize new copy.

Link flow:

- Clicking an existing link offers a quiet destination preview with Edit, Remove and deliberate Open actions. Normal editing clicks must not navigate away.
- The full dialog uses the shared workspace: selected wording in the header context, destination tabs for URL / Content / Page anchor, search/results for content, and a quiet selected-entry detail panel. On narrow screens, stack the details without hiding the primary action.
- Show readable title, path, type, language and publication state. Retain the current authorization/site scope. Draft linking is an explicit product policy with visible status, not a blanket removal of the published-only filter.
- Include link text when no text was selected; changing text on an existing selection is deliberate. Retain identifier-based linking, with human-readable destination context instead of showing raw internal IDs as ordinary form copy.
- Keep button appearance in this same dialog. Default new-tab behavior once for a newly created link; reopening or blurring must preserve explicit `null`, `_self` and `_blank` choices. Treat `nofollow` separately from tab behavior, and retain opener protection for external targets where appropriate.
- Validate inline; only Apply commits the isolated link draft. Cancel/Escape discards it and returns focus to the preserved selection. Do not close after a failed editor command. Disable duplicate submission and handle selection/version changes while open.

Expanded mode uses the same editor instance and input owner, with a readable measure, clear Done/Collapse action, Escape behavior that first closes nested menus, optional word/selection count and an accessible focus boundary. Audit ancestor clipping and sticky-toolbar behavior. Expanding/collapsing must not destroy or reinitialize the editor or move the owning form into an incompatible scope. Persist ordinary edits through the existing mirror immediately; Collapse is not a second Save button.

Acceptance: keyboard-only formatting and link editing, screen-reader naming/errors, correct pressed states, draft Cancel, stable targets, long destination text, right-edge positioning, nested overlays, 390px layout, touch controls and reduced-motion handling. Check real desktop screenshots at 1440px and mobile at 390px after the final UI change.

## G. AI that proposes before it writes

The current `Brando.AI.generate_text/2` returns a completed response synchronously, and the form handler immediately updates the changeset. Replace the rich-text route with a cancellable asynchronous request and explicit review stage. Do not pretend the existing wrapper already streams. Genuine provider streaming can be added behind the same proposal contract; partial output must remain outside the persisted document.

The intended interaction: select a passage, choose Rewrite / Shorten / Continue or enter a short instruction, then see a small working indicator at that passage. The returned proposal appears inline in a contrasting violet/blue treatment with an explicit “AI suggestion” label and a subtle boundary. For replacements, make the original text available alongside the proposal. Provide Accept, Discard and Retry beside it. Use a short, restrained reveal when the result arrives and honor reduced motion; the impressive part is precise placement and reversible control, not a permanent animation.

Represent suggestions as ephemeral editor UI/decorations, not saved formatting marks. Before acceptance, `getHTML`, hidden inputs, Save, draft recovery and live preview contain only authored/accepted content. Acceptance validates/normalizes the proposal through the same HTML/capability contract and applies one transaction; Undo restores the exact prior passage. Discard and Cancel leave the document unchanged. Do not insert internal request IDs, review colors or generated UI into HTML.

Capture request ID, editor/entry identity, base revision, mapped selection and the source text. Ignore canceled, superseded or unmounted responses. If the replacement region changed, keep the suggestion for review or offer regeneration; never overwrite the newer edit automatically. Return to an actionable error/retry state on timeout or provider failure. Keep generation config and keys server-side and send only the configured/requested context. Use the existing form/block commit path on acceptance; this feature does not create a parallel block store. Standard text-field generation can retain its own established behavior until separately migrated.

Acceptance: no persisted or previewed change before Accept; Discard leaves byte-equivalent content where serialization is unchanged; one Undo reverses acceptance; late/canceled responses do nothing; typing during generation cannot be overwritten; errors do not lock the editor; absent AI configuration leaves ordinary editing usable. Test with deterministic fake provider responses, never live model calls in the regression suite.

## H. Cleanup and release validation — item 12

Consolidate SmartText/Typography with explicit locale settings and opt-out, using supported extension APIs. Fix current-color detection/reset and mixed selections. Extract configuration, toolbar state and bridge responsibilities from the large Svelte component without introducing a new state owner.

Measure typing, selection changes and serialization in a long document and a many-editor page before optimizing. Separate document-change work from selection-only toolbar state. If warranted, scope footnote renumbering to reference/order changes and avoid repeated global scans. Never defer the hidden HTML mirror so far that immediate Save or recovery loses keystrokes. Remove dependencies only after checking consumer imports and the deduplication contract.

Keep most regressions in A's fast layers. Retain a small number of real LiveView boundary checks for save/reload/recovery, module configuration application, owner rerender after identifier changes, and accepted AI edits through blocks. Follow the repository commands: source `e2e/.envrc`; rebuild changed JS/CSS with `e2e/assets/backend`'s consumer build; run the relevant focused tests. A full slow suite is not the default development loop. Do not describe simulated transport tests as proof of server recovery.

Release gate: all numbered items have focused coverage, legacy HTML fixtures pass, configuration/DSL round-trips pass, the relevant consumer checks pass, and real UI screenshots have been inspected. Record actual test durations and any remaining product choices. Search/replace, automatic outlines, tables/media inside rich text, comments and character-level collaboration remain separate proposals rather than hidden scope in this plan.

## Planning verification (historical)

The accompanying interactive mockup was exercised in local Chromium: label alternatives, bullet/numbered switching, undo, content-link search/apply/cancel, unsafe-URL feedback, AI accept/discard/undo, and expanded-mode Escape. Light/dark desktop and narrow layouts were checked for overflow and screenshots were inspected. These checks validate the proposal's interactions, not the production Tiptap or LiveView implementation. Application builds and application regression tests were not run for this documentation/mockup-only work.
