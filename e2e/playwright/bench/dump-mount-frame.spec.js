import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'
import fs from 'fs'
import path from 'path'

// Dumps the raw mount frame for the 115-block entry so its composition can be
// measured instead of guessed. Not a benchmark — it asserts nothing, it just
// writes `bench/mount-frame.json` for offline analysis.
//
//   pnpm playwright test --config bench/playwright.bench.config.js bench/dump-mount-frame.spec.js

const IDS = JSON.parse(
  fs.readFileSync(path.join(__dirname, 'fixture-ids.json'), 'utf8')
)

test.use({ viewport: { width: 1400, height: 1200 }, actionTimeout: 20000 })

test('BENCH: dump 115-block mount frame', async ({ page }) => {
  test.setTimeout(600000)

  let biggest = ''
  page.on('websocket', (ws) => {
    ws.on('framereceived', (d) => {
      if (typeof d.payload === 'string' && d.payload.length > biggest.length) {
        biggest = d.payload
      }
    })
  })

  await page.goto(`/admin/pages/update/${IDS.flat['115']}`)
  await syncLV(page, 120000)
  await expect(page.locator('[data-block-uid]').first()).toBeVisible({
    timeout: 120000,
  })
  await page.waitForTimeout(2500)

  fs.writeFileSync(path.join(__dirname, 'mount-frame.json'), biggest)
  console.log(`MOUNT_FRAME_BYTES ${biggest.length}`)
})
