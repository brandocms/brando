import { test, expect } from '../test-support/setupAuth'
import { syncLV, toggleLivePreview, waitForPreviewReady, waitForPreviewUpdate } from '../utils'
import fs from 'fs'
import path from 'path'

// Drives the editor flows on the large fixtures against a traced server, and
// prints one `FLOW <label> <start> <end>` line per step (unix seconds), so
// `elixir e2e/bench/otel/summary.exs --from <start> --to <end>` reads a step's
// traces alone. See e2e/bench/otel/README.md. Run it twice and read the second
// pass: the first after a boot measures module loading and cold caches.
//
//   cd e2e/playwright
//   npx playwright test --config bench/playwright.bench.config.js traced-flows

const IDS = JSON.parse(fs.readFileSync(path.join(__dirname, 'fixture-ids.json'), 'utf8'))

test.use({ viewport: { width: 1400, height: 1200 }, actionTimeout: 30000 })
test.setTimeout(600000)

// The fifth field is the step's wall time in milliseconds, without the pause.
const step = async (label, fun) => {
  const startMs = Date.now()
  await fun()
  const wallMs = Date.now() - startMs
  // Let the batch processor flush and trailing renders finish inside the window.
  await new Promise((resolve) => setTimeout(resolve, 1500))
  console.log(`FLOW ${label} ${Math.floor(startMs / 1000)} ${Math.ceil(Date.now() / 1000)} ${wallMs}`)
}

const entries = [
  ['flat-40', IDS.flat['40'], 'bench-flat-40'],
  ['flat-115', IDS.flat['115'], 'bench-flat-115'],
  ['nested', IDS.nested, 'bench-nested'],
]

for (const [label, id, uri] of entries) {
  test(`traced flows: ${label}`, async ({ page }) => {
    const texts = () =>
      page.locator('.header-block textarea').or(page.locator('[data-block-uid] input[type="text"]:visible'))

    await step(`${label}:mount`, async () => {
      await page.goto(`/admin/pages/update/${id}`)
      await syncLV(page, 120000)
      await expect(page.locator('[data-block-uid]').first()).toBeVisible({ timeout: 120000 })
    })

    await step(`${label}:edit`, async () => {
      const text = texts().first()
      await text.click()
      for (const key of ['A', 'B', 'C']) {
        await text.pressSequentially(key, { delay: 20 })
        await page.waitForTimeout(1200)
        await syncLV(page, 60000)
      }
    })

    await step(`${label}:preview_open`, async () => {
      await toggleLivePreview(page)
      await waitForPreviewReady(page)
    })

    await step(`${label}:edit_with_preview`, async () => {
      const text = texts().first()
      await text.click()
      for (const key of ['D', 'E', 'F']) {
        await text.pressSequentially(key, { delay: 20 })
        await page.waitForTimeout(1200)
        await waitForPreviewUpdate(page)
      }
    })

    await step(`${label}:preview_close`, async () => {
      await toggleLivePreview(page)
    })

    await step(`${label}:save`, async () => {
      await page.getByTestId('split-dropdown-button').click()
      await page.getByRole('button', { name: /Save and continue editing/ }).click()
      await syncLV(page, 120000)
      await page.waitForTimeout(2000)
    })

    await step(`${label}:store_revision`, async () => {
      await page.getByRole('button', { name: 'History', exact: true }).click()
      const drawer = page.locator('[id$="-revisions-drawer"]')
      await expect(drawer).toBeVisible()
      await drawer.getByRole('tab', { name: /Revisions/ }).click()
      const rows = await drawer.locator('[id^="revision-line-"]').count()
      await drawer.getByRole('button', { name: 'Store current editor state' }).click()
      await expect(drawer.locator('[id^="revision-line-"]')).toHaveCount(rows + 1, { timeout: 60000 })
      await drawer.getByRole('button', { name: 'Close' }).click()
    })

    await step(`${label}:public_render`, async () => {
      for (let i = 0; i < 3; i++) {
        const response = await page.request.get(`/${uri}`)
        expect(response.status()).toBeLessThan(500)
      }
    })
  })
}

test('traced flows: listing', async ({ page }) => {
  await step('listing:pages', async () => {
    for (let i = 0; i < 3; i++) {
      await page.goto('/admin/pages')
      await syncLV(page, 60000)
    }
  })
})
