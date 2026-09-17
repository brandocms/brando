# Configuration and gallery refinements

Review captures from the E2E consumer application, 16 September 2026. Desktop
viewport: 1440 × 1000; mobile viewport: 390 × 844. Full-page captures can be taller.
The surrounding sidebar, large blue logo and sample content belong to the E2E
application. Custom Blueprint names use that application's translations.

## Import/Export

The menu and page title now use `Import/Export` (`Import/Eksport` in Norwegian).
Content-type filters support multiple selections and retain selected entries
when filtering. They constrain the catalog before its result limit is applied.
The filters share one labelled surface with checked selections. Each result
shows its author and last update in the site's configured timezone; missing
metadata is labelled explicitly. Author names are fetched in one batch.

Related entries show their actual Blueprint type and the selected entry/field
that references them. Including one moves it into the main export; its own
references can then appear in the related list. Titles such as “Identitet” no
longer have to stand in for a missing type label.
Whole-entry references appear once: in Related entries or the main export.
They remain in the portable dependency graph but are omitted from the other
dependency groups in the export review.

Dependencies are grouped by type with counts and distinct media, definition and
content treatments. “Choose existing on import” replaces the ambiguous “Resolve
on destination” label. It means connecting a reference to an existing destination
record. Included originals and definitions have their own status labels.

The import review offers **Use existing unchanged** alongside create and update.
This is the place to decide whether a shared category or other related entry
already exists. Reuse preserves its fields, content and publication, skips
incoming media used only by that entry, and excludes it from recovery changes.

The failed download was caused by rechecking a generic entry dependency without
passing its schema to the dependency loader. Downloads now validate the full
dependency and every exported entry, and return `brando-content.zip`.

| Review | Desktop | Mobile |
| --- | --- | --- |
| Multiple content types and entry metadata | [Norwegian](export-types-norwegian.png), [detail](export-types-norwegian-detail.png) | [Norwegian](export-types-norwegian-mobile.png) |
| Related entries and dependency groups | [Norwegian](export-relations-norwegian.png), [detail](export-relations-norwegian-detail.png) | [Norwegian](export-relations-norwegian-mobile.png) |
| Reuse without overwriting | [Import review](import-reuse-desktop.png) | |

## Markdown sources

The translated screen follows the configuration workspace layout: compact
controls, ordinary paragraph sizes, bounded panels, and aligned document
metadata. The connection selector retains its dropdown arrow and keyboard
operation. When no connection is available, a setup notice explains that a
developer must configure the repository in the application's `runtime.exs` and
permit the current environment; the unavailable form is disabled.

**From a folder** discovers Markdown files in the selected folder and subfolders.
Editors choose which files to add; existing sources are skipped. Each file is an
individual source. Adding files to GitHub later requires another scan; existing
sources continue their normal synchronization. Initial content can be fetched
with **Refresh from GitHub** or the next configured push. Discovery is limited
to 200 documents and rejects incomplete results.

| Review | Screenshot |
| --- | --- |
| Source form and document metadata | [Desktop](markdown-desktop.png), [detail](markdown-desktop-detail.png) |
| Open repository connection menu | [Keyboard interaction](markdown-connection-options.png) |
| Folder selection | [Desktop](markdown-folder-desktop.png), [detail](markdown-folder-desktop-detail.png), [mobile](markdown-folder-mobile.png) |

## Galleries and globals

Galleries use the shared resource listing treatment, media previews, compact
counts and row actions. Empty toolbars are hidden. Global sets use compact icons,
labels and variable counts. The global-set form uses the settings button and
field proportions, including **Add entry** and **Save**. Variable section headings
are sentence case, help text sits below each input, and disclosure buttons work
with the keyboard. These visual rules are scoped to the global-set screen; the
shared variable disclosure also gains button semantics.

| Review | Desktop | Mobile |
| --- | --- | --- |
| Galleries | [Norwegian](galleries-desktop.png), [detail](galleries-desktop-detail.png) | [Norwegian](galleries-mobile.png) |
| Global sets | [Norwegian](globals-list-desktop.png), [detail](globals-list-desktop-detail.png) | [Norwegian](globals-list-mobile.png) |
| Expanded variable and save controls | [Norwegian](globals-editor-norwegian.png) | [Norwegian](globals-editor-norwegian-mobile.png) |

## Verification

- 35 focused ExUnit tests passed across content transfer, GitHub Markdown
  discovery and the Markdown source LiveView.
- 19 focused Playwright tests passed across import/export, Markdown placement,
  galleries, globals and shared editor modals. The 11 affected browser tests
  were rerun after the final import labels and screenshot changes; the gallery
  screenshot test was rerun after the empty-toolbar fix.
- E2E consumer assets built successfully. Existing Svelte configuration,
  PostCSS `from` and large-chunk warnings remain.
- Changed Elixir files pass the formatter check; `git diff --check` is clean.
- Browser tests cover ZIP download and reimport, multiple type filters,
  unchanged destination reuse, bulk source creation, Norwegian copy, keyboard
  disclosure/selection, field-help separation and mobile overflow.

GitHub discovery is exercised with deterministic provider responses; this review
does not use a live external repository or the production site shown in the
original screenshots.

## Follow-up visual review

The first screenshots exposed inconsistent spacing. The revised captures above
include element screenshots at their original scale, alongside full desktop and
mobile screens. Computed styles and element bounds are collected with each
capture; the [measurement summary](layout-measurements.json) records the final
values.

- Related-entry guidance is one paragraph, followed by a 12px gap to the list.
- Both Markdown helper paragraphs use 13px text with 20px line height. The folder
  selection owns its 16px gaps between instructions, files and its action.
- Document metadata starts 16px below the file path, using a parent grid gap
  rather than a margin vulnerable to the shared workspace reset.
- Galleries have one separator below the header. The first row has no top
  border. On mobile, the item count sits below the title beside the preview.
- Global-set labels and keys have explicit line heights and trimmed text boxes,
  following the existing admin text-metric treatment instead of inheriting the
  link's 22px line height for both lines.

After these corrections, the 28 content-transfer ExUnit tests and 11 affected
browser tests passed. The five screenshot and gallery workflow tests were rerun
after the final typography, timestamp and mobile gallery adjustments, with the
mobile gallery checked again after resolving an inherited grid rule. The E2E
consumer asset build and changed-file formatter checks also passed.
