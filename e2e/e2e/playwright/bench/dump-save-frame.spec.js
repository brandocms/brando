import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'
import fs from 'fs'
import path from 'path'

// Dumps the largest frame received during a save-and-continue on the 115-block
// entry, so its composition can be measured instead of guessed. Asserts
// nothing; writes `bench/save-frame.json`.
//
//   pnpm playwright test --config bench/playwright.bench.config.js bench/dump-save-frame.spec.js

const IDS = JSON.parse(
  fs.readFileSync(path.join(__dirname, 'fixture-ids.json'), 'utf8')
)

test.use({ viewport: { width: 1400, height: 1200 }, actionTimeout: 20000 })

test('BENCH: dump 115-block save frame', async ({ page }) => {
  test.setTimeout(600000)

  let recording = false
  let biggest = ''
  const received = []

  page.on('websocket', (ws) => {
    ws.on('framereceived', (d) => {
      if (!recording || typeof d.payload !== 'string') return
      if (d.payload.includes('"phoenix"')) return
      received.push(d.payload.length)
      if (d.payload.length > biggest.length) biggest = d.payload
    })
  })

  await page.goto(`/admin/pages/update/${IDS.flat['115']}`)
  await syncLV(page, 120000)
  await expect(page.locator('[data-block-uid]').first()).toBeVisible({
    timeout: 120000,
  })
  await page.waitForTimeout(2500)

  // Open the split dropdown outside the recorded window.
  await page.getByTestId('split-dropdown-button').click()

  recording = true
  await page.getByRole('button', { name: /Save and continue editing/ }).click()
  await syncLV(page, 120000)
  await page.waitForTimeout(3000)
  recording = false

  fs.writeFileSync(path.join(__dirname, 'save-frame.json'), biggest)
  console.log(`SAVE_FRAME_BYTES ${biggest.length}`)
  console.log(`SAVE_FRAMES ${JSON.stringify(received.sort((a, b) => b - a).slice(0, 8))}`)
})
