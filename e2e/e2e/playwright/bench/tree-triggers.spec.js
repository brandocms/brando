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
//   pnpm playwright test --config bench/playwright.bench.config.js bench/tree-triggers.spec.js

const IDS = JSON.parse(
  fs.readFileSync(path.join(__dirname, 'fixture-ids.json'), 'utf8')
)

test.use({ viewport: { width: 1400, height: 1200 }, actionTimeout: 20000 })

test('BENCH: tree-wide re-render triggers at 115 blocks', async ({ page }) => {
  test.setTimeout(600000)

  const frames = []
  page.on('websocket', (ws) => {
    ws.on('framereceived', (d) => {
      if (typeof d.payload === 'string' && !d.payload.includes('"phoenix"')) {
        frames.push(d.payload.length)
      }
    })
  })
  const mark = () => frames.length
  const since = (m) => frames.slice(m).reduce((a, n) => a + n, 0)
  const payloads = []
  page.on('websocket', (ws) =>
    ws.on('framereceived', (d) => {
      if (typeof d.payload === 'string' && !d.payload.includes('"phoenix"')) {
        payloads.push(d.payload)
      }
    })
  )

  await page.goto(`/admin/pages/update/${IDS.flat['115']}`)
  await syncLV(page, 120000)
  await expect(page.locator('[data-block-uid]').first()).toBeVisible({
    timeout: 120000,
  })
  await page.waitForTimeout(2500)

  // ---- copy a block: flips clipboard_meta from nil to a map
  const block = page.locator('.entry-block [data-block-uid]').first()
  let m = mark()
  let t0 = Date.now()
  await block.locator('.block-action-dropdown > .block-action').first().click()
  await block
    .locator('.block-action-dropdown-content button', { hasText: 'Copy' })
    .click()
  await syncLV(page, 60000)
  // The copy reaches BlockField through a send_update, so its clipboard_meta
  // assign — and the paste buttons it turns on across every block — land after
  // syncLV returns. Without this wait that traffic is billed to whatever is
  // measured next.
  await page.waitForTimeout(2500)
  console.log(`COPY_BYTES ${since(m)} ms=${Date.now() - t0}`)
  const biggestCopy = payloads.slice(m).sort((a, b) => b.length - a.length)[0]
  if (biggestCopy) {
    fs.writeFileSync(path.join(__dirname, 'copy-frame.json'), biggestCopy)
    console.log(`COPY_FRAME ${biggestCopy.length}`)
  }

  // ---- open the outline drawer: rebuilds every root changeset
  m = mark()
  t0 = Date.now()
  await page.locator('.block-field-dropdown-toggle').first().click()
  await page
    .locator('.block-field-dropdown-content button', { hasText: 'Block outline' })
    .click()
  await syncLV(page, 60000)
  await page.waitForTimeout(500)
  console.log(`OUTLINE_BYTES ${since(m)} ms=${Date.now() - t0}`)
  const biggest = payloads.slice(-frames.length + m).sort((a, b) => b.length - a.length)[0]
  if (biggest) {
    fs.writeFileSync(path.join(__dirname, 'outline-frame.json'), biggest)
    console.log(`OUTLINE_FRAME ${biggest.length}`)
  }
})
