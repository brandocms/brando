#!/usr/bin/env node
// Retakes the admin reference screenshots linked from the docs
// (docs/admin-ui-design.md, docs/admin-ui/**, docs/entry-drafts,
// docs/module-definitions, guides/content_*.md) from a running E2E server.
//
//   cd e2e && source .envrc && MIX_ENV=e2e mix phx.server      # terminal 1
//   cd e2e && source .envrc && node playwright/scripts/admin-ui-references.mjs   # terminal 2
//
// Options: --list prints the catalogue; --only <name>[,<name>…] retakes some
// images (the name is the file name without .png, or a path suffix).
//
// Most images are taken by the E2E specs that cover their screens: the script
// runs those tests (each in its own SQL sandbox, so nothing persists) through
// scripts/admin-ui-references.config.cjs, then copies the named screenshot over
// the reference. Screens no spec captures, or captures in a different frame,
// live in scripts/admin-ui-references.spec.js. Chromium runs with
// --font-render-hinting=none. Every reference is 1× at the stated width; the
// state column says what the image shows.
//
// Not covered: docs/admin-ui/identifier-variants (a design study, see its capture.mjs),
// docs/admin-ui/content-agent-concepts (concept prototypes) and the dated
// audits under docs/audits.
import { spawnSync } from 'node:child_process'
import { copyFileSync, existsSync, mkdirSync, openSync, readSync, closeSync, readdirSync, statSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const here = path.dirname(fileURLToPath(import.meta.url))
const playwrightDir = path.resolve(here, '..')
const repo = path.resolve(playwrightDir, '../..')
const outputDir = path.join(playwrightDir, 'test-results/admin-ui-references')

const spec = {
  authorization: ['tests/config/authorization-tools.spec.js', 'prepares groups and moves a reviewed configuration through export and import'],
  imageRefProcessing: ['scripts/admin-ui-references.spec.js', 'image refs while processing'],
  relatedEntries: ['scripts/admin-ui-references.spec.js', 'related entries: picker and selected field'],
  linkPicker: ['tests/modal-design.spec.js', 'link picker aligns metadata and keeps the selected content through parent updates'],
  blockIdentifiers: ['tests/blocks/block-identifiers.spec.js', 'add, reorder, remove, re-add identifiers and verify persistence'],
  exportTypes: ['tests/configuration/admin-refinements.spec.js', 'type filters preserve selection and related entries can reuse unchanged destinations'],
  markdown: ['tests/configuration/admin-refinements.spec.js', 'Markdown folder selection adds multiple sources and is translated'],
  globals: ['tests/configuration/admin-refinements.spec.js', 'global sets have compact rows and readable variable help at both widths'],
  galleries: ['tests/configuration/admin-refinements.spec.js', 'galleries share the resource listing design'],
  transferRelated: ['tests/configuration/content-transfer.spec.js', 'related entries can be included from export review'],
  transferWhole: ['tests/configuration/content-transfer.spec.js', 'whole entry export, conflict review, draft creation, update and recovery'],
  transferMedia: ['tests/configuration/content-transfer.spec.js', 'media replacements and moves stay in their block context'],
  transferNorwegian: ['tests/configuration/content-transfer.spec.js', 'Norwegian import keeps translated dropdowns and validation after changes'],
  transferFields: ['tests/configuration/content-transfer.spec.js', 'select, export, review, cancel, apply and recover saved content at desktop and mobile widths'],
  moduleFiles: ['tests/configuration/module-files.spec.js', 'export and import DSL bundles with review, updated baselines and responsive controls'],
  moduleConflict: ['tests/configuration/module-files.spec.js', 'rejects malformed files and prevents a stale admin preview from overwriting changes'],
  draftRestored: ['tests/pages/drafts.spec.js', 'recovers a new entry and unsaved block after reload, then resolves the copy on save'],
  draftFailed: ['tests/pages/drafts.spec.js', 'a failed restore survives reload without trapping the editor or overwriting the original'],
  draftModule: ['tests/pages/drafts.spec.js', 'changed modules require review and retain incompatible block content'],
  draftMediaFields: ['tests/pages/draft-media.spec.js', 'image, file and video fields recover selections, replacements and resets without duplicating assets'],
  draftGalleryField: ['tests/pages/draft-media.spec.js', 'a mixed gallery field recovers its order and later deletions'],
  draftGalleryBlock: ['tests/pages/draft-media.spec.js', 'gallery blocks retain mixed media and deletions through draft restore and save'],
  draftRefsVars: ['tests/pages/draft-media.spec.js', 'picture and video refs plus image and file vars recover, save and reset'],
  draftReorder: ['tests/pages/draft-reorder.spec.js', 'recovery shows block and gallery moves, preserves accompanying edits and lets wheel scroll the page'],
  assistantEmpty: ['scripts/admin-ui-references.spec.js', 'assistant: empty workspace'],
  assistantSommerro: ['scripts/admin-ui-references.spec.js', 'assistant: Sommerro proposal from review to applied'],
  assistantNeedsChanges: ['scripts/admin-ui-references.spec.js', 'assistant: proposal that needs changes'],
  aiLooks: ['scripts/admin-ui-references.spec.js', 'ai actions and suggestions: composed sheet'],
}

// [reference path, test, screenshot the test writes, width, language, state]
const D = 'docs/admin-ui/'
const C = 'docs/admin-ui/configuration-refinements/'
const R = 'docs/entry-drafts/'
const M = 'docs/module-definitions/'
const catalogue = [
  [D + 'utilities-reference.png', 'authorization', 'authorization-tools-desktop.png', 1440, 'en', 'Utilities, full page, legacy roles active'],
  [D + 'import-preview.png', 'authorization', 'authorization-import-preview.png', 1440, 'en', 'Utilities group import preview, editor group expanded (element)'],
  [D + 'image-ref-processing-portrait.png', 'imageRefProcessing', 'image-ref-processing-portrait.png', 1440, 'en', 'Portrait image ref while processing (element)'],
  [D + 'image-ref-processing-landscape.png', 'imageRefProcessing', 'image-ref-processing-landscape.png', 1440, 'en', 'Landscape image ref while processing (element)'],
  [D + 'related-entries-selected-1440.png', 'relatedEntries', 'related-entries-selected-1440.png', 1440, 'en', 'Related entries field with two selections (element)'],
  [D + 'related-entries-selected-390.png', 'relatedEntries', 'related-entries-selected-390.png', 390, 'en', 'Related entries field with two selections (element)'],
  [D + 'joined-identifiers-picker.png', 'relatedEntries', 'joined-identifiers-picker.png', 1440, 'en', 'Select entries dialog over the project form, two entries checked'],
  [D + 'link-picker-desktop.png', 'linkPicker', 'link-picker-desktop.png', 1440, 'en', 'Menu item link picker, Content mode, entry selected'],
  [D + 'block-identifiers-1440.png', 'blockIdentifiers', 'block-identifiers-1440.png', 1440, 'en', 'Block datasource with three selected entries (element)'],

  [D + 'ai-actions-and-suggestions.png', 'aiLooks', 'ai-actions-and-suggestions.png', 1440, 'en', 'AI actions and suggestions, composed from the components\' markup (element)'],

  [D + 'assistant-empty-desktop.png', 'assistantEmpty', 'assistant-empty-desktop.png', 1440, 'en', 'Assistant, new conversation'],
  [D + 'assistant-review-desktop.png', 'assistantSommerro', 'assistant-review-desktop.png', 1440, 'en', 'Sommerro proposal ready for review'],
  [D + 'assistant-needs-changes-desktop.png', 'assistantNeedsChanges', 'assistant-needs-changes-desktop.png', 1440, 'en', 'Sommerro proposal blocked by a used slug'],
  [D + 'assistant-library-desktop.png', 'assistantSommerro', 'assistant-library-desktop.png', 1440, 'en', 'Attach from the media library dialog over the proposal'],
  [D + 'assistant-preview-desktop.png', 'assistantSommerro', 'assistant-preview-desktop.png', 1440, 'en', 'Page preview of the proposed Index page'],
  [D + 'assistant-applied-desktop.png', 'assistantSommerro', 'assistant-applied-desktop.png', 1440, 'en', 'Proposal applied'],
  [D + 'assistant-applied-mobile.png', 'assistantSommerro', 'assistant-applied-mobile.png', 390, 'en', 'Proposal applied, full page'],

  [C + 'export-types-norwegian.png', 'exportTypes', 'export-types-norwegian.png', 1440, 'no', 'Import/Export, Page and Fragment filters, Campaign launch selected, full page'],
  [C + 'export-types-norwegian-detail.png', 'exportTypes', 'export-types-norwegian-detail.png', 1440, 'no', 'Same, the entry list (element)'],
  [C + 'export-types-norwegian-mobile.png', 'exportTypes', 'export-types-norwegian-mobile.png', 390, 'no', 'Same, full page'],
  [C + 'export-relations-norwegian.png', 'exportTypes', 'export-relations-norwegian.png', 1440, 'no', 'Export review with related entries and dependencies open, full page'],
  [C + 'export-relations-norwegian-detail.png', 'exportTypes', 'export-relations-norwegian-detail.png', 1440, 'no', 'Same, related entries (element)'],
  [C + 'export-relations-norwegian-mobile.png', 'exportTypes', 'export-relations-norwegian-mobile.png', 390, 'no', 'Same, full page'],
  [C + 'import-reuse-desktop.png', 'exportTypes', 'import-reuse-desktop.png', 1440, 'en', 'Import review reusing the destination page unchanged, full page'],
  [C + 'markdown-desktop.png', 'markdown', 'markdown-desktop.png', 1440, 'no', 'Markdown sources with one source, full page'],
  [C + 'markdown-desktop-detail.png', 'markdown', 'markdown-desktop-detail.png', 1440, 'no', 'Same, document list (element)'],
  [C + 'markdown-connection-options.png', 'markdown', 'markdown-connection-options.png', 1440, 'no', 'Connection select focused from the keyboard, full page'],
  [C + 'markdown-folder-desktop.png', 'markdown', 'markdown-folder-desktop.png', 1440, 'no', 'From a folder: three files found, full page'],
  [C + 'markdown-folder-desktop-detail.png', 'markdown', 'markdown-folder-desktop-detail.png', 1440, 'no', 'Same, setup panel (element)'],
  [C + 'markdown-folder-mobile.png', 'markdown', 'markdown-folder-mobile.png', 390, 'no', 'Same, full page'],
  [C + 'galleries-desktop.png', 'galleries', 'galleries-desktop.png', 1440, 'no', 'Galleries listing with two galleries, full page'],
  [C + 'galleries-desktop-detail.png', 'galleries', 'galleries-desktop-detail.png', 1440, 'no', 'Same, workspace (element)'],
  [C + 'galleries-mobile.png', 'galleries', 'galleries-mobile.png', 390, 'no', 'Same, full page'],
  [C + 'globals-list-desktop.png', 'globals', 'globals-list-desktop.png', 1440, 'no', 'Global sets listing, full page'],
  [C + 'globals-list-desktop-detail.png', 'globals', 'globals-list-desktop-detail.png', 1440, 'no', 'Same, first set title (element)'],
  [C + 'globals-list-mobile.png', 'globals', 'globals-list-mobile.png', 390, 'no', 'Same, full page'],
  [C + 'globals-editor-norwegian.png', 'globals', 'globals-editor-norwegian.png', 1440, 'no', 'Global set editor, Map URL variable expanded, full page'],
  [C + 'globals-editor-norwegian-mobile.png', 'globals', 'globals-editor-norwegian-mobile.png', 390, 'no', 'Same, full page'],

  [D + 'content-transfer-export.png', 'transferWhole', 'entries-export-desktop.png', 1440, 'en', 'Export: Campaign launch selected as a whole entry, full page'],
  [D + 'content-transfer-export-detail.png', 'transferWhole', 'entries-export-detail.png', 1440, 'en', 'Same, workspace to the third card (clip)'],
  [D + 'content-transfer-export-mobile.png', 'transferWhole', 'entries-export-mobile.png', 390, 'en', 'Same, full page'],
  [D + 'content-transfer-review-desktop.png', 'transferWhole', 'entries-review-desktop.png', 1440, 'en', 'Whole-entry import review, fields & content open, full page'],
  [D + 'content-transfer-review-detail.png', 'transferWhole', 'entries-review-detail.png', 1440, 'en', 'Same, the entry card (element)'],
  [D + 'content-transfer-review-mobile.png', 'transferWhole', 'entries-review-mobile.png', 390, 'en', 'Same, full page'],
  [D + 'content-transfer-update-desktop.png', 'transferWhole', 'entries-update-desktop.png', 1440, 'en', 'Import updating Destination page, full page'],
  [D + 'content-transfer-content-diff.png', 'transferWhole', 'entries-content-diff.png', 1440, 'en', 'Same, text diff (element)'],
  [D + 'content-transfer-content-diff-mobile.png', 'transferWhole', 'entries-content-diff-mobile.png', 390, 'en', 'Same, text diff (element)'],
  [D + 'content-transfer-media-diff.png', 'transferMedia', 'entries-media-diff.png', 1440, 'en', 'Media replaced and moved in the text diff (element)'],
  [D + 'content-transfer-media-diff-mobile.png', 'transferMedia', 'entries-media-diff-mobile.png', 390, 'en', 'Same (element)'],
  [D + 'content-transfer-media-diff-norwegian.png', 'transferMedia', 'entries-media-diff-norwegian.png', 1440, 'no', 'Same (element)'],
  [D + 'content-transfer-review-norwegian.png', 'transferNorwegian', 'entries-review-norwegian.png', 1440, 'no', 'Whole-entry import review, full page'],
  [D + 'content-transfer-review-norwegian-detail.png', 'transferNorwegian', 'entries-review-norwegian-detail.png', 1440, 'no', 'Same, the entry card (element)'],
  [D + 'content-transfer-review-norwegian-mobile.png', 'transferNorwegian', 'entries-review-norwegian-mobile.png', 390, 'no', 'Same, full page'],
  [D + 'content-transfer-publication-open.png', 'transferNorwegian', 'entries-publication-open.png', 1440, 'no', 'Same, publication select focused'],
  [D + 'content-transfer-related-desktop.png', 'transferRelated', 'entries-related-desktop.png', 1440, 'en', 'Export review offering a related entry, full page'],
  [D + 'content-transfer-entry-focus.png', 'transferFields', 'transfer-entry-focus.png', 1440, 'en', 'Block-field export: Blocks selected with keyboard focus (element)'],
  [D + 'content-transfer-import.png', 'transferFields', 'transfer-import-desktop.png', 1440, 'en', 'Import tab before a file is chosen, full page'],
  [D + 'content-transfer-import-error.png', 'transferFields', 'transfer-import-error.png', 1440, 'en', 'Import tab with a rejected .txt file, full page'],
  [D + 'content-transfer-import-ready.png', 'transferFields', 'transfer-import-ready.png', 1440, 'en', 'Import tab with a bundle uploaded, full page'],
  [D + 'content-transfer-import-detail.png', 'transferFields', 'transfer-import-detail.png', 1440, 'en', 'Same, workspace to the upload card (clip)'],
  [D + 'content-transfer-import-mobile.png', 'transferFields', 'transfer-import-mobile.png', 390, 'en', 'Same, full page'],
  [D + 'content-transfer-fields-review-desktop.png', 'transferFields', 'transfer-review-desktop.png', 1440, 'en', 'Block-field import review, Compare content open, full page'],
  [D + 'content-transfer-fields-review-mobile.png', 'transferFields', 'transfer-review-mobile.png', 390, 'en', 'Same, full page'],
  [D + 'content-transfer-content-diff-append.png', 'transferFields', 'entries-content-diff-append.png', 1440, 'en', 'Append diff (element)'],
  [D + 'module-files-diff.png', 'moduleFiles', 'module-files-diff.png', 1440, 'en', 'Module file import, class change diff (element)'],
  [D + 'module-files-diff-mobile.png', 'moduleFiles', 'module-files-diff-mobile.png', 390, 'en', 'Same (element)'],

  [M + 'desktop.png', 'moduleFiles', 'module-files-desktop.png', 1440, 'en', 'Modules as files dialog'],
  [M + 'review.png', 'moduleFiles', 'module-files-review.png', 1440, 'en', 'Import preview with an expanded class change'],
  [M + 'complete.png', 'moduleFiles', 'module-files-complete.png', 1440, 'en', 'Import complete with the updated ZIP'],
  [M + 'conflict.png', 'moduleConflict', 'module-files-conflict.png', 1440, 'en', 'Replanned import with a conflict'],
  [M + 'mobile.png', 'moduleFiles', 'module-files-mobile.png', 390, 'en', 'Modules as files dialog, import card in view'],

  [R + 'recovery-restored.png', 'draftRestored', 'recovery-restored.png', 1440, 'en', 'New page restored from a recovery copy, full page'],
  [R + 'recovery-failed.png', 'draftFailed', 'recovery-failed.png', 1440, 'en', 'Recovery panel after a failed restore (element)'],
  [R + 'recovery-module-changed.png', 'draftModule', 'recovery-module-changed.png', 1440, 'en', 'Recovery panel for a changed module (element)'],
  [R + 'recovery-media-diff.png', 'draftMediaFields', 'recovery-media-diff-desktop.png', 1440, 'en', 'Recovery preview of media field changes (element)'],
  [R + 'recovery-media-diff-mobile.png', 'draftMediaFields', 'recovery-media-diff-mobile.png', 390, 'en', 'Same (element)'],
  [R + 'recovery-media-fields.png', 'draftMediaFields', 'recovery-media-fields.png', 1440, 'en', 'Project with recovered image, file and video fields, full page'],
  [R + 'recovery-gallery-field.png', 'draftGalleryField', 'recovery-gallery-field.png', 1280, 'en', 'Recovered mixed gallery field, full page'],
  [R + 'recovery-gallery-block.png', 'draftGalleryBlock', 'recovery-gallery-block.png', 1280, 'en', 'Recovered gallery block, full page'],
  [R + 'recovery-media-refs-vars.png', 'draftRefsVars', 'recovery-media-refs-vars.png', 1280, 'en', 'Recovered picture/video refs and image/file vars, full page'],
  [R + 'recovery-order.png', 'draftReorder', 'recovery-order-desktop.png', 1440, 'en', 'Recovery preview listing block and gallery moves (element)'],
  [R + 'recovery-order-mobile.png', 'draftReorder', 'recovery-order-mobile.png', 390, 'en', 'Same (element)'],
].map(([file, test, output, width, lang, state]) => ({ name: path.basename(file, '.png'), file, test, output, width, scale: 1, lang, state }))

const args = process.argv.slice(2)
const flag = name => args.includes(name)
const value = name => { const i = args.indexOf(name); return i >= 0 ? args[i + 1] : undefined }

if (flag('--list')) {
  for (const shot of catalogue) {
    console.log(`${shot.file}  ${shot.width}px ${shot.scale}x ${shot.lang}  ${shot.state}  [${spec[shot.test][0]}]`)
  }
  process.exit(0)
}

const only = (value('--only') || '').split(',').filter(Boolean)
const matches = shot => only.some(n => n === shot.name || shot.file === n || shot.file.endsWith(n) || shot.file.endsWith(n + '.png'))
const selected = only.length ? catalogue.filter(matches) : catalogue
if (only.length && selected.length === 0) {
  console.error(`No reference matches ${only.join(', ')}. Run with --list.`)
  process.exit(1)
}

if (!process.env.BRANDO_E2E_BASE_URL) {
  console.error('BRANDO_E2E_BASE_URL is not set: run `source .envrc` in e2e/ first, with the E2E server running.')
  process.exit(1)
}

const tests = [...new Set(selected.map(shot => shot.test))].map(key => spec[key])
const files = [...new Set(tests.map(([file]) => file))]
const escape = s => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
const grep = tests.map(([, title]) => escape(title)).join('|')

console.log(`Retaking ${selected.length} reference image(s) from ${tests.length} flow(s) against ${process.env.BRANDO_E2E_BASE_URL}`)
const run = spawnSync(path.join(playwrightDir, 'node_modules/.bin/playwright'),
  ['test', '--config', path.join(here, 'admin-ui-references.config.cjs'), ...files, '--grep', grep],
  { cwd: playwrightDir, stdio: 'inherit', env: { ...process.env, BRANDO_E2E_REUSE_SERVER: 'true' } })

// A test writes its screenshots below its own output folder (with "-retry1"
// when it was retried); take the newest file of each name.
const found = new Map()
const walk = dir => {
  if (!existsSync(dir)) return
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name)
    if (entry.isDirectory()) walk(full)
    else if (entry.name.endsWith('.png')) {
      const previous = found.get(entry.name)
      if (!previous || statSync(full).mtimeMs > statSync(previous).mtimeMs) found.set(entry.name, full)
    }
  }
}
walk(outputDir)

const pngSize = file => {
  const fd = openSync(file, 'r')
  const buffer = Buffer.alloc(24)
  readSync(fd, buffer, 0, 24, 0)
  closeSync(fd)
  return { width: buffer.readUInt32BE(16), height: buffer.readUInt32BE(20) }
}

const missing = []
for (const shot of selected) {
  const source = found.get(shot.output)
  if (!source) { missing.push(shot); continue }
  const target = path.join(repo, shot.file)
  mkdirSync(path.dirname(target), { recursive: true })
  copyFileSync(source, target)
  const { width, height } = pngSize(target)
  const note = width > shot.width * shot.scale ? `  (wider than ${shot.width * shot.scale}px: check)` : ''
  console.log(`  ${shot.file}  ${width}×${height}${note}`)
}

if (missing.length) {
  console.error(`\n${missing.length} image(s) not taken, see the test output above:`)
  for (const shot of missing) console.error(`  ${shot.file}  (${spec[shot.test][1]})`)
}
process.exit(missing.length || run.status ? 1 : 0)
