import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'
import fs from 'fs'
import path from 'path'

// Is the client-side half of an insert morphdom, or browser layout?
//
// `insert-breakdown.spec.js` showed the server round trip is flat in block
// count while the browser main thread is not (0 ms @5 -> 562 ms @115). Those
// two have different fixes, so the difference has to be measured, not guessed.
//
// The experiment: repeat the operation with the block list `display: none`.
// That leaves the DOM exactly as large — same nodes, same morphdom walk — but
// takes it out of layout. If the cost collapses it is layout/paint; if it
// survives it is morphdom.
//
//   pnpm playwright test --config bench/playwright.bench.config.js bench/insert-client-cost.spec.js

const IDS = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixture-ids.json'), 'utf8'))

test.use({ viewport: { width: 1400, height: 1200 }, actionTimeout: 20000 })

const observeLongTasks = (page) =>
  page.evaluate(() => {
    window.__longTasks = []
    new PerformanceObserver((list) => {
      for (const entry of list.getEntries()) window.__longTasks.push(entry.duration)
    }).observe({ entryTypes: ['longtask'] })
  })

const openPickerCost = async (page) => {
  await page.evaluate(() => (window.__longTasks = []))
  const t0 = Date.now()
  await page.getByRole('button', { name: 'Add block' }).last().click()
  await syncLV(page, 60000)
  await page.waitForTimeout(400)
  const wall = Date.now() - t0
  const mainThread = await page.evaluate(() =>
    Math.round(window.__longTasks.reduce((a, d) => a + d, 0))
  )
  // Close again so the next run starts from the same state.
  await page.keyboard.press('Escape')
  await page.locator('.module-picker-extras').waitFor({ state: 'hidden' }).catch(() => {})
  await page.waitForTimeout(400)
  return { wall, mainThread }
}

test('BENCH: insert client cost — layout vs morphdom', async ({ page }) => {
  test.setTimeout(600000)

  await page.goto(`/admin/pages/update/${IDS.flat['115']}`)
  await syncLV(page, 120000)
  await expect(page.locator('[data-block-uid]').first()).toBeVisible({ timeout: 120000 })
  await page.waitForTimeout(2500)
  await observeLongTasks(page)

  const visible = await openPickerCost(page)
  console.log(`CLIENT_COST visible   wall=${visible.wall} mainThread=${visible.mainThread}`)

  const nodesBefore = await page.evaluate(
    () => document.querySelectorAll('.entry-block *').length
  )

  // Same DOM, out of layout.
  await page.addStyleTag({ content: '.entry-block { display: none !important; }' })
  await page.waitForTimeout(1000)

  const hidden = await openPickerCost(page)
  const nodesAfter = await page.evaluate(
    () => document.querySelectorAll('.entry-block *').length
  )

  console.log(`CLIENT_COST hidden    wall=${hidden.wall} mainThread=${hidden.mainThread}`)
  console.log(`CLIENT_COST domNodes  before=${nodesBefore} after=${nodesAfter}`)
})
