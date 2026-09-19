import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'
import fs from 'fs'
import path from 'path'

// Opens one block entry and holds the LiveView connected, so an out-of-band
// observer can inspect the server-side process. LiveComponents share the parent
// LiveView process heap, so block editor memory is only visible from the BEAM.
//
//   BENCH_ENTRY=115 HOLD_MS=45000 pnpm playwright test \
//     --config bench/playwright.bench.config.js --grep "hold entry"

const IDS = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixture-ids.json'), 'utf8'))
const KEY = process.env.BENCH_ENTRY || '115'
const HOLD_MS = Number(process.env.HOLD_MS || 45000)

test.describe('BENCH: hold entry open', () => {
  test.setTimeout(HOLD_MS + 180000)
  test.use({ viewport: { width: 1400, height: 1200 }, actionTimeout: 20000 })

  test(`hold entry ${KEY}`, async ({ page }) => {
    const id = KEY === 'nested' ? IDS.nested : IDS.flat[KEY]
    expect(id, `no fixture id for "${KEY}"`).toBeTruthy()

    await page.goto(`/admin/pages/update/${id}`)
    await syncLV(page, 120000)
    await expect(page.locator('[data-block-uid]').first()).toBeVisible({ timeout: 120000 })
    await page.waitForTimeout(3000)

    const nodes = await page.locator('[data-block-uid]').count()
    console.log(`HOLD_READY entry=${KEY} id=${id} blockNodes=${nodes}`)

    await page.waitForTimeout(HOLD_MS)
    console.log(`HOLD_DONE entry=${KEY}`)
  })
})
