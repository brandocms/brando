# Tiptap implementation · 9 September 2026

Implemented on `codex/tiptap-editor-care`, based on `c9c29c9f5` after rebasing onto
`next`. The [audit](audit.md) remains historical; the [plan](implementation-plan.md)
records the agreed scope.

## Delivered

- **Reliable editing:** coherent ProseMirror dependencies, one-time hook subscriptions,
  cleanup on destruction, targeted external replacements, composition deferral,
  selection mapping and preserved history through unrelated LiveView updates.
  Footnote insertion retains selected words. Presence locks prevent actual edits.
- **Links and identifiers:** shared client/server URL fixtures and validation,
  a single link mark for text/button appearance, preserved classes and authored
  wording, reliable HTML parsing for URL changes, locked owner updates, cache
  invalidation and queued rendering for ordinary rich-text fields as well as refs.
- **Configuration:** authoring restrictions cover shortcuts, commands, input rules
  and paste while retaining compatible legacy markup. Basic/Caption/Article
  presets add to individual choices. Module reference settings include a real
  default-text preview. Styles retain their public classes and use collision-safe
  internal keys that never enter HTML. Empty configuration remains distinct from
  implicit defaults.
- **Anchors and paste:** readable IDs, caret removal, outer anchor spans across
  formatting, duplicate protection, anchor editing and fragment copying. Paste
  preserves semantic emphasis and approved attributes, rejects unsafe links and
  provides text fallback for unsupported structures or foreign footnotes.
- **Authoring UI:** compact paragraph/style menu, bullet-default split list control,
  contextual nesting actions, opt-in blockquote, color state/reset, undo/redo,
  keyboard toolbar/menu navigation, labels/errors, focus and disabled states.
- **Link workspace:** URL/Content/Page anchor modes, an isolated draft, authored
  text and appearance, new-tab/nofollow controls, preserved search and target,
  inline errors, unavailable-destination feedback, selection-safe Apply/Cancel
  and an editor acknowledgment before closing. Uses the existing shared modal.
- **Expanded editing:** the same editor and owning input, focus containment,
  nested Escape behavior, word count and preserved history.
- **AI proposals:** asynchronous Rewrite/Shorten/Continue with configured context,
  a violet inline review panel, cancellation, retry, stale-result protection,
  Accept/Discard and one-step undo. Unaccepted proposals never enter HTML,
  draft recovery or preview. Text refs opt in through `Brando.AI` `block_text` config.

HTML remains the persisted format. Presets supplement existing settings.
Blockquote is excluded from all shipped presets. Anchor names remain readable;
style keys and AI request IDs are never saved as text or styling.

## Verification

| Layer | Result | Measured time |
| --- | --- | --- |
| Pure Node configuration/URL/style tests | 3 passed | 59 ms |
| Real Svelte/Tiptap + hook, mocked LiveView transport | 20 passed | 5.2 s |
| Additional nested-keyboard and 20-editor checks | 2 passed | 2.9 s including a fresh Vite start |
| Focused ExUnit: rich text, link dialog, AI, inputs, module sync/DSL, form recovery | 63 passed | 2.4 s after compilation |
| Client/server event contract | 2 passed | 0.3 s after compilation |
| Actual consumer DB: normal destination mutation, ref/field rewrite, owner cache and render job | 1 passed | 0.4 s after compilation |
| CMS: module creation with additive presets | passed | 2.6 s test body |
| CMS: Norwegian footnotes and ordinary-field note save/reload | 2 passed | 3.9 s combined test bodies |
| CMS: safe/unsafe links, unrelated edits, undo/redo, expanded mode, identifier save/reload, responsive dialog | passed | approximately 5 s test body |
| Actual E2E consumer production build | passed | 4.25 s |

The focused CMS invocations also start Phoenix and compile changed files; those
costs are excluded from the test-body times above. No full E2E suite was run.
The existing Browserslist age, PostCSS `from` and bundle-size warnings remain.

The 600-paragraph microbenchmark (66,520 bytes of HTML) mounted in 52 ms;
30 edits measured 1.5 ms median / 2.5 ms p95. On a page with 20 editor instances,
30 edits measured 0.2 ms median / 0.8 ms p95. Both verified an immediately current
hidden HTML input; the latter verified unchanged neighbors. These are local
Chromium transaction measurements, not end-to-end latency or rendering budgets.

### Repeat the focused checks

Use the project's configured Elixir/Erlang runtime. Source `e2e/.envrc` before
consumer commands. The browser fixture reuses the actual consumer Vite/Svelte
configuration and has no Phoenix, database, seeds or application login.
The Node and browser fixture suites also run in CI using the first legacy E2E
job's installed consumer dependencies, before the full application shard.

```sh
node --test test/javascript/tiptap.test.mjs

mix test test/brando/rich_text_test.exs \
  test/brando_admin/components/form/rich_text_ai_test.exs \
  test/brando_admin/components/form/tiptap_link_dialog_test.exs \
  test/brando_admin/components/form/input_test.exs \
  test/brando/content/module_sync_test.exs \
  test/brando/content/definition_test.exs \
  test/brando_admin/live/form_recovery_test.exs \
  test/brando_admin/wire_contract_test.exs

cd e2e
source .envrc
MIX_ENV=test mix test test/unit/rich_text_identifier_test.exs
cd assets/backend
pnpm build
cd ../../e2e/playwright
pnpm exec playwright test --config tiptap.config.js
pnpm exec playwright test tests/blocks/tiptap-editor.spec.js --retries=0
pnpm exec playwright test tests/configuration/modules.spec.js --grep 'create a simple text module' --retries=0
pnpm exec playwright test tests/blocks/block-footnotes.spec.js --grep 'Blueprint rich text|uses Norwegian' --retries=0
```

Run the browser configurations sequentially because the application suite clears
its results directory. The fast suite places its artifacts under
`test-results/tiptap-components`. When the consumer unit application and browser
application run simultaneously, give the unit application a separate
`BRANDO_E2E_PORT` before sourcing `.envrc`.

## Actual UI captures

Fresh consumer screenshots were inspected at 1440×900 and 390×844. The mobile
capture shows the scrolled details panel with primary actions still accessible.
The background navigation and its seeded logo are the existing E2E application.

- [URL dialog](screenshots/link-url-desktop.png)
- [Content workspace](screenshots/link-content-desktop.png)
- [Content workspace at 390px](screenshots/link-content-mobile.png)
- [Expanded editor](screenshots/expanded-editor-desktop.png)
- [Expanded editor at 390px](screenshots/expanded-editor-mobile.png)

### Expanded-editor refinement

Following visual feedback, the expanded editor uses the shared modal proportions:
field title and Done action, a bounded writing surface on a quiet sage background,
consistent document padding, a subtle focus border, and matching Heroicons for
Undo/Redo. Header, toolbar and footer remain visible while long text scrolls.
The same editor instance and HTML input remain in place. The desktop and mobile
captures above reflect this refinement. Focused identity/keyboard checks, the
actual CMS save/reload flow and the consumer build passed.

## Compatibility and limits

- True external content/schema replacements reset local undo history; ordinary
  echoes and unrelated field changes retain it. Changing module preview settings
  deliberately rebuilds its schema while retaining authored HTML and selection.
- Rich-text AI now requests plain prose. Older prompts requesting HTML should be
  updated. The current provider wrapper returns a completed response; the review
  reveal is an animation, not provider token streaming. Deterministic provider
  and editor tests ran; no live model requests were made. The complete provider
  round-trip through a real block was not exercised against a live AI service.
- New UI strings use Gettext and default to English where translations are
  absent. Existing Norwegian footnote translations were verified in the CMS.
- Unsafe changed rich-text HTML is rejected at its changeset boundary. Unrelated
  raw HTML fields are not scrubbed. Foreign pasted footnote content is not cloned.
- Identifier discovery still scans candidate HTML containing identifier metadata;
  only exact parsed matches are locked and rewritten. No database migration or
  new reference index is introduced by this change.

Configuration examples and AI migration guidance are in
[the Blueprint guide](../../../guides/blueprints.md).
