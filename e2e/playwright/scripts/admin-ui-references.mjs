#!/usr/bin/env node
// Retakes the admin reference screenshots linked from the docs
// (.claude/skills/brando-admin-ui, guides/content_*.md) from a running E2E
// server.
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
  assistantEmpty: ['scripts/admin-ui-references.spec.js', 'assistant: empty workspace'],
  assistantExampleHotel: ['scripts/admin-ui-references.spec.js', 'assistant: Example Hotel proposal from review to applied'],
  assistantNeedsChanges: ['scripts/admin-ui-references.spec.js', 'assistant: proposal that needs changes'],
  aiLooks: ['scripts/admin-ui-references.spec.js', 'ai actions and suggestions: composed sheet'],
}

// [reference path, test, screenshot the test writes, width, language, state]
const D = 'docs/admin-ui/'
const catalogue = [
  [D + 'utilities-reference.png', 'authorization', 'authorization-tools-desktop.png', 1440, 'en', 'Utilities, full page, legacy roles active'],
  [D + 'import-preview.png', 'authorization', 'authorization-import-preview.png', 1440, 'en', 'Utilities group import preview, editor group expanded (element)'],
  [D + 'image-ref-processing-portrait.png', 'imageRefProcessing', 'image-ref-processing-portrait.png', 1440, 'en', 'Portrait image ref while processing (element)'],
  [D + 'image-ref-processing-landscape.png', 'imageRefProcessing', 'image-ref-processing-landscape.png', 1440, 'en', 'Landscape image ref while processing (element)'],
  [D + 'related-entries-selected-1440.png', 'relatedEntries', 'related-entries-selected-1440.png', 1440, 'en', 'Related entries field with two selections (element)'],
  [D + 'related-entries-selected-390.png', 'relatedEntries', 'related-entries-selected-390.png', 390, 'en', 'Related entries field with two selections (element)'],
  [D + 'joined-identifiers-picker.png', 'relatedEntries', 'joined-identifiers-picker.png', 1440, 'en', 'Select entries dialog over the project form, two entries checked'],

  [D + 'ai-actions-and-suggestions.png', 'aiLooks', 'ai-actions-and-suggestions.png', 1440, 'en', 'AI actions and suggestions, composed from the components\' markup (element)'],

  [D + 'assistant-empty-desktop.png', 'assistantEmpty', 'assistant-empty-desktop.png', 1440, 'en', 'Assistant, new conversation'],
  [D + 'assistant-review-desktop.png', 'assistantExampleHotel', 'assistant-review-desktop.png', 1440, 'en', 'Example Hotel proposal ready for review'],
  [D + 'assistant-needs-changes-desktop.png', 'assistantNeedsChanges', 'assistant-needs-changes-desktop.png', 1440, 'en', 'Example Hotel proposal blocked by a used slug'],
  [D + 'assistant-library-desktop.png', 'assistantExampleHotel', 'assistant-library-desktop.png', 1440, 'en', 'Attach from the media library dialog over the proposal'],
  [D + 'assistant-preview-desktop.png', 'assistantExampleHotel', 'assistant-preview-desktop.png', 1440, 'en', 'Page preview of the proposed Index page'],
  [D + 'assistant-applied-desktop.png', 'assistantExampleHotel', 'assistant-applied-desktop.png', 1440, 'en', 'Proposal applied'],
  [D + 'assistant-applied-mobile.png', 'assistantExampleHotel', 'assistant-applied-mobile.png', 390, 'en', 'Proposal applied, full page'],
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
