**Tiptap audit · 8 September 2026**

Brando has a sound choice of editor and a useful CMS integration. Keep Tiptap, Svelte, the existing content picker, and the separation between rich text and Villain blocks. The highest-value work is to make content transformations, editor lifecycle, and available controls predictable. Several reproducible correctness defects should precede a visual refresh.

This audit covers commit `443943ad703bbea8f3be2765e5d327497e76cb20`: the Svelte editor, LiveView hook, custom extensions, paste sanitizer, rich-text and text-block rendering, link dialog, HTML persistence, identifier updates, draft recovery integration, CSS, and relevant tests. It compares the implementation with current official Tiptap and WAI guidance.

The repository locks Tiptap packages to **3.23.4** and Svelte to **5.55.5**. The component and hook were copied unchanged to a temporary Vite fixture and exercised in Chromium using those exact installed versions from the main checkout. LiveView transport and hook-event cleanup were simulated; the anchor prompt was stubbed. The observations and source hashes are recorded in [evidence.json](/Users/trond/.codex/worktrees/a5f5/brando_next/docs/audits/tiptap-2026-09-08/evidence.json). The main checkout and this worktree have identical asset package manifests and lockfiles. These diagnostics reproduced component behavior; they are not a passing application regression suite. A separate dependency experiment, described below, forced one ProseMirror model instance only in the temporary fixture.

This worktree had no installed application dependencies or running E2E server. Full Phoenix save/reload, multiuser timing, and real admin screenshots at 1440px and 390px were not verified during this audit. UI recommendations below come from the actual markup, CSS, component behavior, and the approved [admin design guide](/Users/trond/.codex/worktrees/a5f5/brando_next/docs/admin-ui-design.md). No application implementation was changed.

**The architecture is broadly appropriate.**

Tiptap owns the editable DOM within `phx-update="ignore"`; LiveView owns the surrounding form. The hook reads the hidden input's current value property when mounting. These choices avoid competing DOM owners and an already-documented stale-attribute problem. The component destroys its editor when Svelte unmounts. [Hook](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/hooks/TipTap/index.js:53), [rich-text rendering](/Users/trond/.codex/worktrees/a5f5/brando_next/lib/brando_admin/components/form/input.ex:388).

The HTML mirror updates on document changes, with a 300ms LiveView debounce. Drawer navigation can explicitly commit the owning form, including sibling values. Draft recovery captures the visible raw form values, including hidden rich-text mirrors. These are useful existing mechanisms; adding a second Tiptap autosave store would create unnecessary state ownership problems. [Update mirror](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/components/TipTap/TipTap.svelte:119), [commit](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/hooks/TipTap/index.js:112), [draft capture](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/hooks/Form/draftRecovery.js:13).

Content-aware links retain identifier IDs and have URL-update infrastructure. Footnotes use stable reference UIDs, atomic nodes, and separate content blocks; numbering is derived rather than persisted as literal numbers. Named style presets are a good fit for a CMS. The shared link workspace and existing AI actions should be retained and improved. These are stronger foundations than a generic formatting toolbar.

**Fix these content and lifecycle defects first.**

| Priority | Finding | Evidence | Recommended result |
| --- | --- | --- | --- |
| P1 | Mixed ProseMirror model instances break typed list/quote shortcuts | Runtime, lockfile, controlled deduplication experiment | Deduplicate the dependency graph and verify the consumer bundle |
| P1 | Button links bypass ordinary-link URL validation | Runtime + source | Shared URL policy across link creation, parsing, serialization, and server validation |
| P1 | Adding a footnote replaces selected text | Runtime | Preserve the selected text and insert the reference after it |
| P1 | Editor remounts discard undo history | Runtime + server call sites | Keep unrelated editors mounted; define update/history semantics by change source |
| P1 | Destroyed hooks remain in the global component registry | Runtime + source | Unregister on destruction and register handlers once |
| P2 | Ordinary links and button links can produce invalid or lost markup | Runtime | A single link model, or mutually exclusive marks with robust parsing |
| P2 | Configured extensions do not constrain authoring | Runtime, including keyboard shortcut | Explicit authoring profiles with a legacy-content preservation policy |
| P2 | Paste cleanup removes semantic formatting and changes link behavior | Runtime | Normalize supported semantics before removing presentation noise |
| P2 | Jump anchors duplicate IDs and cannot reliably be removed at a caret | Runtime | Stable node-level anchors or atomic anchor nodes |
| P2 | Editable field and toolbar accessibility are incomplete | Runtime markup + source | Named editor, connected validation state, usable keyboard controls |
| P2 | Link dialog overwrites existing target preferences | Source | Preserve explicit choices and validate/normalize submitted URLs |
| P2 | Style names can collide; “Clear style” leaves inline presets intact | Runtime | Collision-safe identifiers and accurate clearing semantics |
| P3 | SmartText uses an obsolete extension hook; color state is wrong | Runtime + installed core source | Remove redundant dead code and derive state correctly |

**Resolve the ProseMirror dependency split before other editor work.**

The lockfile resolves `prosemirror-model` 1.25.4 and 1.25.5, two transform versions, and two view versions. In the unmodified component fixture, typing `1. `, `- `, or `> ` raised `RangeError: Can not convert <> to a Fragment (looks like multiple versions of prosemirror-model were loaded)` and failed to create the expected list or quote. Heading and typography controls provided useful passing comparisons. [Dependency graph](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/pnpm-lock.yaml:2475).

Forcing all `prosemirror-model` imports to the same installed 1.25.5 module in the temporary Vite fixture removed the errors and made ordered lists, bullets, and blockquotes work. This is a controlled confirmation of the model-instance mismatch. The repository and consumer configuration were not changed. Reconcile the lockfile dependency graph, keep ProseMirror imports consistent, and verify the actual E2E consumer bundle and its input rules; merely aligning the top-level Tiptap package versions is insufficient. This is an observed component/bundling failure, not a claim that a deployed consumer was tested.

**1. Button links need the same safety contract as ordinary links.**

Selecting text and calling `setLink({href: 'javascript:void(0)'})` returned `false`. Calling `setButton` with the same harmless test URL returned `true` and serialized the URL unchanged into an anchor. The custom Button extension is a plain `Mark`; its `validate`, `protocols`, `autolink`, and `openOnClick` options have no built-in effect unless its implementation consumes them. Its commands and renderer do not validate the URL. [Button extension](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/components/TipTap/extensions/Button/index.js:28).

The link dialog accepts an arbitrary string and passes it through. The text-block changeset casts HTML as a string, the text parser returns it directly, and the public rich-text helper renders HTML as raw. No shared rich-text sanitation boundary was found in these inspected paths. This makes client-side paste cleanup insufficient as a server trust boundary. The audit demonstrated unsafe serialization, not execution against a published page or an unauthorized write. [Dialog payload](/Users/trond/.codex/worktrees/a5f5/brando_next/lib/brando_admin/components/form/input/blocks/tiptap_link_dialog.ex:266), [text changeset](/Users/trond/.codex/worktrees/a5f5/brando_next/lib/brando/villain/blocks/text_block.ex:65), [parser](/Users/trond/.codex/worktrees/a5f5/brando_next/lib/brando/villain/parser.ex:444), [public rendering](/Users/trond/.codex/worktrees/a5f5/brando_next/lib/brando/html.ex:894).

Use a common URL validator and preserve Tiptap's maintained checks when extending Link. Validate the rich-text contract server-side while retaining approved classes, identifiers, and footnote attributes. Applying a generic sanitizer that drops those attributes would introduce different data-loss bugs. Ordinary Link already exposes a maintained `isAllowedUri` contract. [Official Link documentation](https://tiptap.dev/docs/editor/extensions/marks/link).

**2. Footnotes must preserve selected content.**

Starting with “Audit text”, selecting “Audit”, and dispatching the hook's normal footnote insertion event produced a footnote followed by “ text”. `insertContent` replaces the current selection. The reference should normally go at the selection's end, leaving the selected words intact. Capture the intended position before opening the drawer, map it if transactions occur, and insert the reference there. [Insertion handler](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/hooks/TipTap/index.js:95).

Keep the existing UID-based reference architecture. Add explicit behavior for copying references between editors and entries: copying the marker alone must not silently create a dangling reference or accidentally share another entry's definition. Footnote nodes are currently parsed even when the add-footnote button is disabled; a disabled-profile fixture rendered an interactive marker. Legacy references may need preservation, but editing availability and missing-definition handling must be deliberate.

**3. Replace broad remounting with a precise editor-update contract.**

A local edit made `can().undo()` true; calling the hook's `remount()` made it false. A fresh Editor necessarily loses its old history and selection. This matters beyond explicit draft replacement: receiving remote entry-field changes triggers a global component-remount event, and AI generation for one rich-text field also uses the global remount path. An unrelated update can therefore rebuild other rich-text editors. [Hook remount](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/hooks/TipTap/index.js:189), [global dispatch](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/buildApplication.js:165), [remote field update](/Users/trond/.codex/worktrees/a5f5/brando_next/lib/brando_admin/components/form.ex:185), [AI remount](/Users/trond/.codex/worktrees/a5f5/brando_next/lib/brando_admin/components/form.ex:5188).

Define updates with editor ID, document revision, and source: local typing, acknowledged echo, remote replacement, draft restore, AI replacement, or schema change. Ignore equivalent echoes. Update only the affected editor. Preserve selection where meaningful; queue or explicitly resolve remote replacement during local composition. AI replacement should normally be one undoable user action. Draft restore or switching entries may intentionally start a new history.

Simply replacing every remount with `setContent` is insufficient: remote changes, undo history, stale acknowledgements, and focused local edits need explicit semantics. If using `setContent`, specify `emitUpdate`; Tiptap 3 defaults it to true, which can create an echo loop in a server-driven update path. [Official setContent documentation](https://tiptap.dev/docs/editor/api/commands/content/set-content).

**4. Clean up hook registration and event subscriptions.**

`mounted()` appends the hook to `app.components`; `destroyed()` never removes it. The global remount handler iterates that array without checking connection state. The fixture retained every destroyed hook. That creates a retention path for detached DOM and allows later global remounts to revisit obsolete components. Separately, every `remount()` calls `setupLinkHandler()` again on the same live hook. One remount increased link-event registrations from one to two. [Registration](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/hooks/TipTap/index.js:7), [cleanup](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/hooks/TipTap/index.js:189).

Use a registry with explicit removal, and register hook event listeners once per hook lifetime. Store/remove event references if registration must change. Centralize HTML synchronization: applying a link to selected text currently emits two hidden-input events, from `onUpdate` and the link handler's explicit synchronization. This is avoidable duplication, though the audit did not measure two server round trips.

**5. Represent button appearance as a link property if practical.**

Applying Link and then Button to the same text produced nested `<a>` elements. Neither mark excludes the other. Reloading `<a class="action-button extra" href="/path">CTA</a>` produced plain text: Button requires an exact class attribute, while CustomLink rejects any anchor containing `action-button`. [Button parser](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/components/TipTap/extensions/Button/index.js:9), [CustomLink parser](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/components/TipTap/TipTap.svelte:438).

A single Link extension with a supported appearance attribute would share validation, identifier metadata, removal, and editing behavior. If keeping separate marks, make them mutually exclusive, use class-token matching, and implement conversion explicitly. Test partial selections, already-linked text, extra classes, and save/reload. Retain compatibility with existing `action-button` HTML.

**6. Make editor profiles truthful without destroying legacy content.**

`extensions="p|bold"` hid other toolbar controls but still loaded headings, ordered lists, underline, code, blockquote, alignment, footnotes, and the whole TextStyleKit. The fixture accepted H6 and underline, and the numbered-list keyboard shortcut worked. Typography substitutions also continued under this restricted configuration. The documentation describes this option as extensions “to enable”, so the present behavior violates the advertised contract. [Configuration processing](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/components/TipTap/TipTap.svelte:125), [Editor construction](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/components/TipTap/TipTap.svelte:456), [documented option](/Users/trond/.codex/worktrees/a5f5/brando_next/lib/brando/blueprint/forms.ex:395).

There are smaller inconsistencies: `all` omits alignment and H4; H5/H6 are supported by the schema and style presets but lack normal heading choices; clearing marks is always shown; an empty extension list becomes an empty string and falls back to all controls. TextStyleKit also enables font family, font size, background color, and line height. A “paragraph-only” fixture preserved a 40px Comic Sans span with a red background and custom line height when loaded as HTML. [TextStyleKit documentation](https://tiptap.dev/docs/editor/extensions/functionality/text-style-kit).

Build one configuration registry that drives toolbar controls, commands, shortcuts, input/paste rules, and supported attributes. Suggested presets are caption, basic, article, and source note, with application overrides. Distinguish what authors may create from what the editor must preserve when opening existing content. Turning off schema extensions indiscriminately can strip existing content on the next edit; Tiptap's schema discards unsupported structures. Add a compatibility/content-check strategy before narrowing schemas. [Schema documentation](https://tiptap.dev/docs/editor/core-concepts/schema).

**7. Paste needs semantic normalization, not only sanitation.**

The cleaner strips all `style` attributes. The controlled fixture `<span style="font-weight:bold;font-style:italic">…</span>` became plain text. This demonstrates loss of style-encoded emphasis, including that kind of HTML produced by office editors; it is not a claim that all Word or Google Docs paste loses formatting. Supported semantic `<strong>` and `<em>` should survive, and style-based equivalents should be converted before styles are discarded. [Paste cleaner](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/components/TipTap/extensions/PasteCleaner/HTMLInputParser.js:275).

The cleaner also removes `target`. Pasting a link with `target="_self"` reconstructed it as `_blank` through Link's defaults. Conversely, arbitrary paragraph classes survive. Identifier IDs and footnote data attributes survived the tested cleaner, so removing all data attributes is not the current problem.

Define expected outcomes for internal Brando copy, external rich HTML, plain text, lists, table-shaped content, and media. Preserve meaningful emphasis, lists, approved styles, and intentional link behavior. Strip foreign presentation classes and unsupported styles. If a table or media item cannot be represented, offer a meaningful fallback rather than silent flattening. Add real clipboard fixtures from Word, Google Docs, web pages, and another Brando field.

**8. Anchors should identify positions, not freely splittable marked text.**

Bolding the middle of an anchored word serialized three separate spans with the same `id="chapter"`. Clearing an anchor with a caret inside it left the anchor unchanged because `unsetMark` was called without extending the mark range. Both behaviors were reproduced. [JumpAnchor](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/components/TipTap/extensions/JumpAnchor/index.js:32), [prompt action](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/components/TipTap/TipTap.svelte:356).

Use stable IDs on headings/paragraphs for section anchors; use an atomic inline node when arbitrary positions are necessary. Validate uniqueness and provide copy-link, rename, and remove actions. Preserve old IDs during migration so existing incoming links keep working. A browser prompt gives no useful duplicate-ID validation or page-anchor discovery.

**9. Bring rich text into the form accessibility contract.**

Tiptap supplies `role="textbox"` and `tabindex="0"`; these are already present. The integration does not give the editable element an accessible name, `aria-multiline`, required/invalid state, or a relationship to its instructions and errors. The field's visible label points at the hidden form input, which is not a substitute for naming the editor. Existing generic input tests explicitly exempt hidden inputs from ARIA state, so they do not cover this boundary. [Field rendering](/Users/trond/.codex/worktrees/a5f5/brando_next/lib/brando_admin/components/form/input.ex:382), [generic accessibility tests](/Users/trond/.codex/worktrees/a5f5/brando_next/test/brando_admin/components/form/input_accessibility_test.exs:103).

Most toolbar buttons have accessible names, but active state is only a CSS class. Add `aria-pressed`, appropriate disabled state from `can()`, and a named toolbar with deliberate keyboard navigation. The block-type popover has no explicit expanded/control relationship or menu navigation. The color control has no accessible name and is hidden with `visibility:hidden`, preventing normal keyboard access. The editable region explicitly removes its outline; no replacement Tiptap focus styling was found. Verify the full application's keyboard focus treatment before final visual sign-off. [Toolbar](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/components/TipTap/TipTap.svelte:549), [CSS](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/css/components/Form/Input/TipTap.css:83).

Use the WAI toolbar pattern: one tab stop into the toolbar, arrow navigation between controls, and a documented shortcut from the document to its toolbar. Preserve selection while moving into controls and returning to the document. Localize the currently hardcoded English toolbar labels alongside Brando's translated dialog copy. [WAI toolbar guidance](https://www.w3.org/WAI/ARIA/apg/patterns/toolbar/).

**10. Make link editing respect the author's choices.**

An existing absolute URL intentionally saved for the current tab has `target: null`. Reopening the dialog interprets that as “infer a default” and switches the checkbox on. Every URL blur also recalculates the target, overriding the author's explicit preference. Track the distinction between a new link's default and an existing/user-selected value. [Target calculation](/Users/trond/.codex/worktrees/a5f5/brando_next/lib/brando_admin/components/form/input/blocks/tiptap_link_dialog.ex:223).

A bare `example.com` passed to `setLink` remained a relative href. Trim input, explain accepted URL forms, and normalize hostnames deliberately. Prefer HTTPS for autolink defaults. Show errors when a URL is rejected rather than closing the dialog after a failed command. Keep `nofollow` as an editorial/SEO choice separate from “open in a new tab”; the current dialog ties them together. Support link text when nothing is selected: applying a link at an empty selection currently creates no visible linked text until the user types.

Add a small contextual link preview with destination, Edit, Remove, and a deliberate Open action. Use the existing full content picker for browsing CMS entries. Test selection preservation through nested dialogs and server updates. The picker currently restricts results to published content; consider draft destinations with clear status when authors prepare interlinked content before publication.

**11. Finish the custom-style contract.**

`foo-bar` and `foo_bar` are distinct valid class names but both generate extension name `style_span_foo_bar`. The fixture emitted Tiptap's duplicate-extension warning. Case changes also collapse names. Use a collision-safe encoding or stable identifier. [Style-name generation](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/components/TipTap/TipTap.svelte:169).

“Clear style” only clears paragraph/heading classes; it left a selected inline preset in place. The same dropdown contains both kinds of style, so the action is misleading. “Clear marks” also removes semantic link, button, and anchor marks, while leaving node styles and alignment. Define separate, plainly named actions such as “Remove text formatting” and “Reset paragraph style”, with a deliberate decision about retaining links and anchors. [Clear behavior](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/components/TipTap/TipTap.svelte:315).

The block-style configuration accepts icons but the current dropdown renders only labels. `Input.rich_text` does not forward the text-block style configuration, so ordinary rich-text fields cannot use the same preset contract. Share the configuration interface. Preview named styles only when their actual consumer CSS is available; the existing wrapper-level Lede treatment is separate from `p.lede` presets.

**12. Remove obsolete code and avoid premature performance changes.**

SmartText defines `inputRules()`, whereas the installed Tiptap 3 manager reads `addInputRules()`. Its custom rules are inactive. Typography already performs many of the same substitutions, which masks the dead code. Prefer one configurable Typography extension and test locale-appropriate quotation marks and opt-out behavior. [SmartText](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/components/TipTap/extensions/SmartText/index.js:16), [Extension API](https://tiptap.dev/docs/editor/extensions/custom-extensions/create-new/extension).

The color-active query compares the color attribute with boolean `true`. A selected red span still reported inactive in the fixture. Derive presence/current color from the actual attribute and provide a reset-to-default action. [Transaction state](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/src/components/TipTap/TipTap.svelte:524).

Every document update serializes HTML and scans footnote markers; every transaction recalculates numerous active states plus all style presets. With many editors this is a plausible cost, not a measured latency defect. Profile long articles and many-block pages before changing it. Keep the hidden HTML mirror current so immediate Save and recovery remain correct. Limit footnote renumbering to relevant reference/order changes and scope active-state calculation to configured controls where measurements justify it.

Split the 800-line Svelte file along actual responsibilities: editor configuration/extensions, toolbar UI/state, and the LiveView bridge. Normalize config once. Prefer `@tiptap/pm` imports consistently over separately declared ProseMirror packages, and remove unused package/import entries after checking consumers. The lockfile has one state version but multiple model/transform/view versions; the separate input-rule experiment above demonstrates why checking only the state version is insufficient.

**What functionality is actually missing?**

| Capability | Current state | Recommendation |
| --- | --- | --- |
| Bold, italic, paragraphs, headings, bullets | Present | Keep; make profiles and current state clear |
| Undo/redo | Engine and shortcuts present; toolbar controls absent; history lost on remount | Surface controls after lifecycle fixes |
| Numbered lists | Engine and shortcut present; toolbar absent | Add beside bullet lists |
| List indentation/outdent | Underlying list commands available | Expose in list context and document shortcuts |
| Blockquote | StarterKit supports it; no toolbar control | Useful article-profile addition |
| Underline, strike, inline code, code block, rule | Loaded but largely invisible | Explicitly offer or restrict by profile |
| Internal links and styled button links | Present | Repair shared model, editing and validation |
| Footnotes | Present, with separate note blocks and recovery flows | Fix selection handling; specify clipboard ownership |
| Anchors | Present but structurally fragile | Repair before adding automatic heading links/outline |
| Named styles | Text-block support exists | Unify field/block support and show current preset |
| Placeholder and editing guidance | No editor placeholder wired | Add useful, profile-specific empty-state guidance |
| Word/character count | No editor feature found | Optional footer; selection count for long text |
| Search/replace and document outline | No editor feature found | Add for long article workflows if needed |
| Focus/expanded editing mode | No editor-specific mode found | Useful for long content and small drawer editors |
| Tables | No Tiptap table schema/UI | Product decision: structured table block or restricted accessible table editing |
| Images, galleries, video, embeds | Owned by Brando's block/media system | Keep that ownership; improve insertion handoff if needed |
| AI generation | Already integrated with rich-text fields | Make replacement previewable and undoable |
| Draft recovery and peer synchronization | Existing Brando mechanisms | Strengthen integration; do not duplicate them |
| Character-level simultaneous coediting, comments, tracked changes | No Tiptap integration found | Separate product work, only if editorial demand warrants it |

**The toolbar should explain the document, not make users decode it.**

Use a visible block-type label such as “Paragraph” or “Heading 2”, followed by grouped controls for emphasis, lists, and insertion. Give custom styles a readable current label. Keep less common subscript, superscript, anchors, color, and clear-format actions in a More menu or relevant profile. Add Undo and Redo with correct availability. Shortcuts should appear in tooltips and help.

A reasonable article-toolbar order is `Paragraph ▾ · Bold · Italic · Link | Bullets · Numbers · Quote | Style ▾ · More ▾ | Undo · Redo`. Treat this as an information hierarchy, not a pixel-approved design. Captions and source notes need fewer controls. Contextual controls can supplement the fixed toolbar, but must remain keyboard-accessible.

Retain the existing readable 70ch measure. Give an empty editor a comfortable click target and a profile-appropriate minimum height. Use a restrained input boundary, a distinct focus state, and a quiet toolbar surface. Consolidate the hardcoded black/gray/blue values into existing admin tokens. The current 32px buttons are reasonable for compact desktop use; provide at least the design guide's 40px coarse-pointer treatment and test zoom.

The field wrapper uses `overflow:hidden`, while its toolbar uses sticky positioning. That ancestor can prevent the intended page-scroll stickiness. Popovers are positioned once from the trigger's coordinates and do not implement viewport collision handling or repositioning on scroll/resize. Test long style labels, a narrow drawer, the right edge of the viewport, and mobile keyboard opening. Use the existing Floating UI dependency where native positioning is insufficient. These are source-backed layout risks, not failures observed in a full admin screenshot.

The approved link-picker workspace should remain the deep-selection flow. Simple URL editing should take fewer steps, with clear selected text and a destination preview. Replace technical terms like “Clear marks” with the task the author is performing. Ensure body text, headings, nested lists, custom styles, links, and buttons have predictable spacing in the real consumer stylesheet.

**HTML storage is defensible; formalize its contract before considering a migration.**

Tiptap supports HTML persistence and recommends JSON for easier structured processing. Brando already renders HTML through its Elixir content pipeline, so moving every field to JSON would be a substantial migration rather than a prerequisite for improving the editor. Keep HTML for the first improvement stages. Specify supported markup and custom attributes, add round-trip fixtures, and give future schema changes a migration policy. [Tiptap persistence guidance](https://tiptap.dev/docs/editor/core-concepts/persistence).

The existing identifier URL rewrite for ordinary rich-text fields uses a regex that assumes `href` appears before `data-identifier-id`. Tiptap currently serializes that order, but imported or transformed HTML need not. Prefer an HTML-aware rewrite, and test reordered attributes, escaping, and multiple links. This is a source-backed fragility, not a reproduced database failure. [Identifier rewrite](/Users/trond/.codex/worktrees/a5f5/brando_next/lib/brando/content/blocks.ex:457).

Consider versioned JSON as the editing source, with derived HTML for publishing, only when structured transformations, collaboration, or document interchange justify it. Avoid maintaining independently editable HTML and JSON copies.

Brando's current peer synchronization is at field/block level. Tiptap's Collaboration extension uses Yjs and has different history semantics; it would require a deliberate architecture project. Meanwhile, review the current presence lock: its CSS prevents pointer interaction but does not itself disable keyboard editing in an already-focused editor. No concurrent-write exploit was reproduced here. Treat this as a conflict-handling test requirement, with server ownership still authoritative. [Lock CSS](/Users/trond/.codex/worktrees/a5f5/brando_next/assets/css/components/Form/Input/Blocks/Block.css:2064), [Tiptap collaboration guidance](https://tiptap.dev/docs/editor/extensions/functionality/collaboration).

**Implement in four reviewable stages.**

1. **Protect content and editor state.** Reconcile the ProseMirror dependency graph, repair button URL validation and link conversion/parsing, preserve selection on footnote insertion, clean up hook registration, replace broad remounts, and fix anchor removal/ID splitting. Add focused regressions with each fix.
2. **Define the editing contract.** Introduce authoring profiles with legacy-content preservation, normalize paste, unify style configuration, correct target preferences, and connect rich-text accessibility and localization to the existing form system.
3. **Refine the everyday UI.** Build the grouped toolbar, visible type/style labels, undo/redo, numbered lists, quote control, contextual link editing, keyboard help, accessible color presets, and responsive treatment. Verify actual consumer screenshots.
4. **Add editorial tools selectively.** Word count, expanded mode, outline/search, table workflows, AI review/undo, and possibly collaboration/comments. Choose from observed author needs rather than exposing every extension.

**Validation should exercise the state boundaries and real author actions.**

Existing tests cover basic text entry/persistence, rich-text link apply/cancel/remove, footnote drawers and recovery, and peer synchronization. Examples are [modal design](/Users/trond/.codex/worktrees/a5f5/brando_next/e2e/e2e/playwright/tests/modal-design.spec.js:175), [footnotes](/Users/trond/.codex/worktrees/a5f5/brando_next/e2e/e2e/playwright/tests/blocks/block-footnotes.spec.js), [multiuser sync](/Users/trond/.codex/worktrees/a5f5/brando_next/e2e/e2e/playwright/tests/blocks/block-multiuser-sync.spec.js:197), and [unused collection recovery](/Users/trond/.codex/worktrees/a5f5/brando_next/e2e/e2e/playwright/tests/blocks/block-unused-collections.spec.js). Generic form accessibility tests do not verify the rich-text editable surface.

Add a focused editor matrix covering:

- Type and save immediately; type and open a drawer before the debounce; save with a link modal recently closed; recover after reconnect.
- Undo after local formatting, AI replacement, unrelated remote changes, explicit restore, and a component update; verify intentional history boundaries.
- Repeated mount/destroy/remount without retained registry entries or duplicate link subscriptions.
- Links and buttons in both directions, empty/nonempty selections, rejected protocols, bare hostnames, relative URLs, identifiers, target choices, and HTML round trips.
- Footnote insertion over selected text, undo/redo, cross-field/entry paste, missing definitions, renumbering after block reorder, and drawer return focus.
- Anchor formatting splits, unique IDs, removal at a caret, rename, copy/paste, and preservation of published fragment URLs.
- Restricted profiles via toolbar, keyboard, paste, load, and schema upgrades; old content must not silently disappear.
- Named styles with hyphens/underscores/case variants, mixed selections, inline clearing, and application-defined visual styles.
- Real office/web clipboard fixtures, nested lists, Unicode, nonbreaking spaces, CJK/IME composition, and content outside the supported schema.
- Named textbox and validation announcements, keyboard-only toolbar/dialog operation, visible focus, 200% zoom, touch controls, and Chrome/Firefox/Safari behavior.
- Real admin views at 1440px and 390px, long labels and documents, scrolling toolbar/popovers, nested editors, and mobile keyboard opening.

For repository JS/CSS work, source `e2e/.envrc`, build through `e2e/assets/backend`, and run the affected E2E scenarios. Preserve the existing relevant tests. A standalone root-asset build is not a validation gate. Performance work should begin with traces of representative long articles and many-editor pages, including serialization, transaction handling, renumbering, LiveView traffic, and retained editor instances.
