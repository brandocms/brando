import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'
import fs from 'fs'
import path from 'path'
const IDS = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixture-ids.json'), 'utf8'))
test.use({ viewport: { width: 1400, height: 1200 }, actionTimeout: 20000 })
test('dump entry fanout', async ({ page }) => {
  test.setTimeout(300000)
  const frames = []
  page.on('websocket', (ws) =>
    ws.on('framereceived', (d) => {
      if (typeof d.payload === 'string' && !d.payload.includes('"phoenix"')) frames.push(d.payload)
    })
  )
  await page.goto(`/admin/pages/update/${IDS.entry_consumers}`)
  await syncLV(page, 120000)
  await expect(page.locator('[data-block-uid]').first()).toBeVisible({ timeout: 120000 })
  await page.waitForTimeout(2500)
  const title = page.getByLabel('Title', { exact: true })
  await title.click()
  await title.pressSequentially('A', { delay: 20 })
  await page.waitForTimeout(1200)
  await syncLV(page, 60000)
  await page.waitForTimeout(500)
  const mark = frames.length
  await title.pressSequentially('B', { delay: 20 })
  await page.waitForTimeout(1500)
  await syncLV(page, 60000)
  fs.writeFileSync(path.join(__dirname, 'entry-fanout-frames.json'), JSON.stringify(frames.slice(mark), null, 2))
  console.log('DUMPED', frames.length - mark)
})
