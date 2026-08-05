import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'
import fs from 'fs'
import path from 'path'

// Measures the two actions the plan flags as tree-wide re-render triggers:
// copying a block (changes `clipboard_meta`, which every block's paste button
// reads) and opening the outline drawer (which rebuilds every root changeset).
// Neither is a payload the normal bench captures, because neither happens
// during a mount/edit/insert/save cycle.
//
// Each is now split three ways — server round trip, browser main thread, and
// the remainder — because the wall clock conflates them and they have
// different fixes. That split is what showed insert latency was browser
// layout rather than server render work.
//
//   pnpm playwright test --config bench/playwright.bench.config.js bench/tree-triggers.spec.js

const IDS = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixture-ids.json'), 'utf8'))

test.use({ viewport: { width: 1400, height: 1200 }, actionTimeout: 20000 })

test('BENCH: tree-wide re-render triggers at 115 blocks', async ({ page }) => {
  test.setTimeout(600000)

  const frames = []
  page.on('websocket', (ws) => {
    ws.on('framesent', (d) => {
      if (typeof d.payload === 'string' && !d.payload.includes('"phoenix"')) {
        frames.push({ dir: 'out', t: Date.now(), p: d.payload })
      }
    })
    ws.on('framereceived', (d) => {
      if (typeof d.payload === 'string' && !d.payload.includes('"phoenix"')) {
        frames.push({ dir: 'in', t: Date.now(), p: d.payload })
      }
    })
  })

  await page.goto(`/admin/pages/update/${IDS.flat['115']}`)
  await syncLV(page, 120000)
  await expect(page.locator('[data-block-uid]').first()).toBeVisible({ timeout: 120000 })
  await page.waitForTimeout(2500)

  // Long tasks are main-thread blocks over 50 ms. At 115 blocks the document is
  // ~21 000 nodes, and anything that forces a layout pass over it costs
  // hundreds of milliseconds no matter what the server did.
  await page.evaluate(() => {
    window.__longTasks = []
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) window.__longTasks.push(entry.duration)
    }).observe({ entryTypes: ['longtask'] })
  })

  const measured = {}
  const copyBytes = () => measured.COPY

  const measure = async (label, fn, settleMs) => {
    const mark = frames.length
    await page.evaluate(() => (window.__longTasks = []))
    const t0 = Date.now()
    await fn()
    await syncLV(page, 60000)
    // Both of these land through a `send_update`, so their diff arrives after
    // syncLV returns. Measured without an explicit wait, that traffic is billed
    // to whatever runs next — which first made copy look free.
    await page.waitForTimeout(settleMs)
    const wall = Date.now() - t0
    const mainThread = await page.evaluate(() =>
      Math.round(window.__longTasks.reduce((a, d) => a + d, 0))
    )

    const slice = frames.slice(mark)
    const inbound = slice.filter((f) => f.dir === 'in')
    const firstOut = slice.find((f) => f.dir === 'out')
    const lastIn = inbound[inbound.length - 1]
    const bytes = inbound.reduce((a, f) => a + f.p.length, 0)
    const biggest = inbound.map((f) => f.p).sort((a, b) => b.length - a.length)[0]

    console.log(
      `${label} bytes=${bytes} biggestFrame=${biggest ? biggest.length : 0} ` +
        `wall=${wall} server=${firstOut && lastIn ? lastIn.t - firstOut.t : '?'} ` +
        `mainThread=${mainThread}`
    )
    measured[label] = bytes
    return biggest
  }

  // ---- copy a block: flips clipboard_meta from nil to a map
  const block = page.locator('.entry-block [data-block-uid]').first()
  const copyFrame = await measure(
    'COPY',
    async () => {
      await block.locator('.block-action-dropdown > .block-action').first().click()
      await block
        .locator('.block-action-dropdown-content button', { hasText: 'Copy' })
        .click()
    },
    2500
  )
  if (copyFrame) fs.writeFileSync(path.join(__dirname, 'copy-frame.json'), copyFrame)

  // Budget, not a target. Copying a block cost 849 KB in one frame until the
  // paste buttons stopped taking `clipboard_meta` as a per-block assign; it is
  // now ~400 B. A regression here is invisible in normal use — the copy still
  // works, it just re-renders the whole tree again — so it has to be asserted.
  expect(copyBytes(), 'copy payload at 115 blocks (budget 20 000 B)').toBeLessThan(20_000)

  // ---- open the outline drawer: rebuilds every root changeset
  const outlineFrame = await measure(
    'OUTLINE',
    async () => {
      await page.locator('.block-field-dropdown-toggle').first().click()
      await page
        .locator('.block-field-dropdown-content button', { hasText: 'Block outline' })
        .click()
    },
    1500
  )
  if (outlineFrame) fs.writeFileSync(path.join(__dirname, 'outline-frame.json'), outlineFrame)
})

// Separate entry, because none of the modules the other fixtures use mention
// `entry` — `Block.may_read_entry?/2` excludes every one of them, so a fan-out
// measured there reads zero however expensive the fan-out is. `/bench-entry-
// consumers` makes all 115 blocks consumers: the honest worst case.
test('BENCH: entry-field fan-out at 115 consuming blocks', async ({ page }) => {
  test.setTimeout(600000)

  const frames = []
  page.on('websocket', (ws) => {
    ws.on('framesent', (d) => {
      if (typeof d.payload === 'string' && !d.payload.includes('"phoenix"')) {
        frames.push({ dir: 'out', t: Date.now(), n: d.payload.length })
      }
    })
    ws.on('framereceived', (d) => {
      if (typeof d.payload === 'string' && !d.payload.includes('"phoenix"')) {
        frames.push({ dir: 'in', t: Date.now(), n: d.payload.length })
      }
    })
  })

  await page.goto(`/admin/pages/update/${IDS.entry_consumers}`)
  await syncLV(page, 120000)
  await expect(page.locator('[data-block-uid]').first()).toBeVisible({ timeout: 120000 })
  await page.waitForTimeout(2500)

  await page.evaluate(() => {
    window.__longTasks = []
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) window.__longTasks.push(entry.duration)
    }).observe({ entryTypes: ['longtask'] })
  })

  const typeInto = async (label, field) => {
    await field.click()
    // Prime — the first keystroke in a field costs more than the ones after it.
    await field.pressSequentially('A', { delay: 20 })
    await page.waitForTimeout(1200)
    await syncLV(page, 60000)
    await page.waitForTimeout(500)

    const mark = frames.length
    await page.evaluate(() => (window.__longTasks = []))
    const t0 = Date.now()
    await field.pressSequentially('B', { delay: 20 })
    await page.waitForTimeout(1200)
    await syncLV(page, 60000)
    const wall = Date.now() - t0
    const mainThread = await page.evaluate(() =>
      Math.round(window.__longTasks.reduce((a, d) => a + d, 0))
    )

    const slice = frames.slice(mark)
    const inbound = slice.filter((f) => f.dir === 'in')
    const firstOut = slice.find((f) => f.dir === 'out')
    const lastIn = inbound[inbound.length - 1]

    const bytes = inbound.reduce((a, f) => a + f.n, 0)
    console.log(
      `${label} bytes=${bytes} ` +
        `frames=${slice.length} wall=${wall} ` +
        `server=${firstOut && lastIn ? lastIn.t - firstOut.t : '?'} mainThread=${mainThread}`
    )
    return bytes
  }

  const title = page.getByLabel('Title', { exact: true })
  await typeInto('ENTRY_FIELD read', title)

  // Assert the effect, not just the cost. A cheap fan-out and a fan-out that
  // silently reaches nobody produce the same byte count — which is how the
  // fan-out shipped `nil` to every block for however long: `change` was read
  // from the top-level params instead of the entry's, so any block rendering
  // `{{ entry.title }}` blanked as soon as you typed in the title.
  const typed = await title.inputValue()
  await expect(page.locator('[b-tpl="bench-entry-consumer"]').first()).toContainText(typed)

  // The same keystroke in a field no module reads must not reach any block —
  // registration carries the field list, so this is the fan-out's actual bound.
  // Budget: a field no module reads must not reach a single block. Registration
  // carries each block's field list, so this is the fan-out's actual bound —
  // without it, typing anywhere in the entry costs the full 276 KB.
  const unread = await typeInto('ENTRY_FIELD unread', page.getByLabel('URI', { exact: true }))
  expect(unread, 'fan-out for an unread entry field (budget 15 000 B)').toBeLessThan(15_000)
})
