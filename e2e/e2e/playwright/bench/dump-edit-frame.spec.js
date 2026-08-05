import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'
import fs from 'fs'
import path from 'path'

// Dumps the raw *steady-state* single-edit diff for the 115-block entry, in
// both directions, so the per-edit payload can be measured instead of guessed.
// Asserts nothing — writes `bench/edit-frames.json` for offline analysis.
//
//   pnpm playwright test --config bench/playwright.bench.config.js bench/dump-edit-frame.spec.js
//
// The first edit after a block mounts costs more than the ones after it, so
// this primes with one keystroke and dumps the second.

const IDS = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixture-ids.json'), 'utf8'))

test.use({ viewport: { width: 1400, height: 1200 }, actionTimeout: 20000 })

test('BENCH: dump 115-block single-edit frames', async ({ page }) => {
  test.setTimeout(600000)

  const frames = []
  page.on('websocket', (ws) => {
    ws.on('framesent', (d) => {
      if (typeof d.payload === 'string') frames.push({ dir: 'out', p: d.payload })
    })
    ws.on('framereceived', (d) => {
      if (typeof d.payload === 'string') frames.push({ dir: 'in', p: d.payload })
    })
  })

  await page.goto(`/admin/pages/update/${IDS.flat['115']}`)
  await syncLV(page, 120000)
  await expect(page.locator('[data-block-uid]').first()).toBeVisible({ timeout: 120000 })
  await page.waitForTimeout(2500)

  const texts = (await page.locator('.header-block textarea').count())
    ? page.locator('.header-block textarea')
    : page.locator('[data-block-uid] input[type="text"]:visible')

  const first = texts.first()
  await first.click()
  await page.waitForTimeout(700)
  await first.pressSequentially('A', { delay: 20 })
  await page.waitForTimeout(1400)
  await syncLV(page, 60000)
  await page.waitForTimeout(600)

  const mark = frames.length
  await first.pressSequentially('B', { delay: 20 })
  await page.waitForTimeout(1400)
  await syncLV(page, 60000)

  const slice = frames.slice(mark).filter((f) => !f.p.includes('"phoenix"'))
  fs.writeFileSync(
    path.join(__dirname, 'edit-frames.json'),
    JSON.stringify(slice, null, 2)
  )

  const bytes = (dir) =>
    slice.filter((f) => f.dir === dir).reduce((a, f) => a + f.p.length, 0)
  console.log(
    `EDIT_FRAMES in=${bytes('in')} out=${bytes('out')} frames=${slice.length}`
  )
})
