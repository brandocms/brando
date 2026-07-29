import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'
import fs from 'fs'
import path from 'path'

// Block editor benchmark. NOT part of the regression suite — it lives outside
// `tests/` so a normal `test_e2e.sh` run never picks it up.
//
// Prerequisites:
//   cd e2e && source .envrc && MIX_ENV=e2e mix run priv/repo/e2e_seeds_large.exs
//
// Run:
//   cd e2e/e2e/playwright && pnpm playwright test --config bench/playwright.bench.config.js
//
// Answers the question the architecture decision rests on: does per-edit cost
// stay flat as an entry grows, or does it scale with block count? See
// .claude/plans/block-editor-architecture/assessment.md

// Playwright transpiles specs to CJS, so __dirname is available here. Using
// import.meta.url instead would flip this file to real ESM and break the
// (CJS-transpiled) test-support imports above.
const IDS = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixture-ids.json'), 'utf8'))

// Playwright's actionTimeout defaults to unlimited, so a mistyped locator
// silently blocks for the whole test timeout instead of failing fast. Cap it.
test.use({ viewport: { width: 1400, height: 1200 }, actionTimeout: 20000 })

const results = []

const recorder = (page) => {
  const frames = []
  page.on('websocket', (ws) => {
    ws.on('framesent', (d) => {
      if (typeof d.payload === 'string') frames.push({ dir: 'out', n: d.payload.length, p: d.payload })
    })
    ws.on('framereceived', (d) => {
      if (typeof d.payload === 'string') frames.push({ dir: 'in', n: d.payload.length, p: d.payload })
    })
  })

  const mark = () => frames.length
  const since = (m) => {
    const slice = frames.slice(m).filter((f) => !f.p.includes('"phoenix"'))
    const out = slice.filter((f) => f.dir === 'out')
    const inc = slice.filter((f) => f.dir === 'in')
    return {
      out: out.reduce((a, f) => a + f.n, 0),
      in: inc.reduce((a, f) => a + f.n, 0),
      frames: slice.length,
      maxFrame: inc.reduce((a, f) => Math.max(a, f.n), 0),
    }
  }
  return { mark, since }
}

const measureEntry = async (page, label, entryId, expectedBlocks) => {
  const { mark, since } = recorder(page)
  const row = { entry: label, blocks: expectedBlocks }

  // ---- mount: navigate into the editor and wait until it is interactive
  let m = mark()
  let t0 = Date.now()
  await page.goto(`/admin/pages/update/${entryId}`)
  await syncLV(page, 120000)
  await expect(page.locator('[data-block-uid]').first()).toBeVisible({ timeout: 120000 })
  await page.waitForTimeout(2500)
  row.mount = { ...since(m), ms: Date.now() - t0 }

  const rendered = await page.locator('[data-block-uid]').count()
  row.renderedBlockNodes = rendered

  // Header-ref blocks expose a textarea; container/multi blocks only have
  // string vars, so fall back to any text input inside a block.
  const texts = (await page.locator('.header-block textarea').count())
    ? page.locator('.header-block textarea')
    : page.locator('[data-block-uid] input[type="text"]:visible')

  // ---- single debounced edit on the FIRST block (worst case for a long list)
  const firstText = texts.first()
  await firstText.click()
  await page.waitForTimeout(700)
  // prime, so we measure steady state rather than the once-per-mount extra
  await firstText.pressSequentially('A', { delay: 20 })
  await page.waitForTimeout(1400)
  await syncLV(page, 60000)
  await page.waitForTimeout(600)

  m = mark()
  t0 = Date.now()
  await firstText.pressSequentially('B', { delay: 20 })
  await page.waitForTimeout(1400)
  await syncLV(page, 60000)
  row.editFirst = { ...since(m), ms: Date.now() - t0 }

  // ---- same edit on the LAST text block
  const textCount = await texts.count()
  if (textCount > 1) {
    const lastText = texts.nth(textCount - 1)
    await lastText.scrollIntoViewIfNeeded()
    await lastText.click()
    await page.waitForTimeout(700)
    await lastText.pressSequentially('A', { delay: 20 })
    await page.waitForTimeout(1400)
    await syncLV(page, 60000)
    await page.waitForTimeout(600)

    m = mark()
    t0 = Date.now()
    await lastText.pressSequentially('B', { delay: 20 })
    await page.waitForTimeout(1400)
    await syncLV(page, 60000)
    row.editLast = { ...since(m), ms: Date.now() - t0 }
    await lastText.blur()
    await syncLV(page, 60000)
  }

  // ---- structural op: insert a block at the end
  m = mark()
  t0 = Date.now()
  await page.getByRole('button', { name: 'Add block' }).last().click()
  await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
  await page.getByRole('button', { name: 'Styled Header' }).click()
  await syncLV(page, 60000)
  row.insert = { ...since(m), ms: Date.now() - t0 }

  // ---- save
  await page.waitForTimeout(800)
  // Save-and-continue lives behind the split dropdown; open it outside the
  // measured window so only the save round trip is timed.
  await page.getByTestId('split-dropdown-button').click()
  m = mark()
  t0 = Date.now()
  await page.getByRole('button', { name: /Save and continue editing/ }).click()
  await syncLV(page, 120000)
  await page.waitForTimeout(3000)
  row.save = { ...since(m), ms: Date.now() - t0 }

  results.push(row)
  console.log('BENCH_ROW ' + JSON.stringify(row))
  return row
}

// Budgets, not targets. Each is ~10% above what was measured on 2026-07-29,
// on fixtures that now carry config- and hidden-placement vars, so ordinary
// noise passes and a real regression fails. Raising one is a deliberate act — record why in
// `.claude/plans/block-editor-architecture/plan.md`.
//
// Mount is the number that matters: it is what an editor waits through when
// opening an entry, and it is the one that scales with block count.
const BUDGETS = {
  'flat-5': { mount: 360_000, edit: 13_000, save: 60_000 },
  'flat-40': { mount: 1_650_000, edit: 13_000, save: 65_000 },
  'flat-115': { mount: 4_380_000, edit: 13_000, save: 75_000 },
  // Nested mount swings ~9% run to run, so its headroom is wider on purpose.
  nested: { mount: 2_150_000, edit: 3_200, save: 235_000 },
}

const assertBudget = (row) => {
  const budget = BUDGETS[row.entry]
  if (!budget) return

  expect(
    row.mount.in,
    `mount payload for ${row.entry} (budget ${budget.mount} B)`
  ).toBeLessThan(budget.mount)

  expect(
    row.editFirst.in,
    `single-edit diff for ${row.entry} (budget ${budget.edit} B)`
  ).toBeLessThan(budget.edit)

  // The save frame used to be the largest in the editor: the entry struct is
  // replaced on save, and letting that reach every block re-rendered all of
  // them. Guard it — a regression here is invisible in normal use, because the
  // save still succeeds, just slowly.
  expect(
    row.save.in,
    `save payload for ${row.entry} (budget ${budget.save} B)`
  ).toBeLessThan(budget.save)
}

test.describe('BENCH: block editor cost vs entry size', () => {
  test.setTimeout(600000)

  for (const [size, id] of Object.entries(IDS.flat)) {
    test(`flat entry, ${size} root blocks`, async ({ page }) => {
      assertBudget(await measureEntry(page, `flat-${size}`, id, Number(size)))
    })
  }

  test('nested entry, 40 roots x 3 levels', async ({ page }) => {
    assertBudget(await measureEntry(page, 'nested', IDS.nested, 40))
  })

  test.afterAll(() => {
    if (results.length) console.log('\nBENCH_RESULTS ' + JSON.stringify(results, null, 2))
  })
})
