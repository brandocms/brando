// Design review capture for the content assistant. Not a test: it drives a
// running e2e server (BASE) and writes screenshots to OUT. Each run creates the
// Sommerro case; on a reused database the second run shows the proposal's
// "slug already in use" state instead and stops before applying.
import { chromium } from '@playwright/test'

const BASE = process.env.BASE
const OUT = process.env.OUT || '/tmp/assistant-review'
const shot = (page, name, opts = {}) => page.screenshot({ path: `${OUT}/${name}.png`, ...opts })
const settle = page => page.waitForTimeout(700)

const browser = await chromium.launch()
const context = await browser.newContext({ baseURL: BASE, viewport: { width: 1440, height: 1000 } })
const page = await context.newPage()

await page.goto('/admin/login')
await page.locator('input[type="email"]').fill('admin@brandocms.com')
await page.locator('input[type="password"]').fill('brandocms')
await page.locator('input[type="password"]').press('Enter')
await page.waitForURL(/\/admin$/)

if (process.env.SYNC !== 'no') {
  await page.goto('/admin/config/utils')
  await page.getByRole('button', { name: 'Sync identifiers' }).click()
  await settle(page)
}

await page.goto('/admin/assistant')
await settle(page)
await shot(page, '01-empty')

await page.locator('#assistant-upload input.file-input').setInputFiles(['./fixtures/image.jpg', './fixtures/image2.jpg'])
await page.locator('.assistant-attachment:not(.is-pending)').nth(1).waitFor({ timeout: 30000 })
await settle(page)
await shot(page, '02-attached')
// The upload drawer clears itself four seconds after the last file.
await page.waitForTimeout(4500)

await page.getByLabel('Message').fill('Put image1 on the Index page and create a case called Sommerro with image2')
await page.getByLabel('Message').press('Enter')
await page.locator('.assistant-proposal').waitFor({ timeout: 30000 })
await page.waitForTimeout(1500)
await shot(page, '03-review')
await shot(page, '03-review-full', { fullPage: true })

await page.locator('.assistant-card').first().getByRole('button', { name: 'Preview page' }).click()
await page.waitForTimeout(5000)
await shot(page, '04-preview')

await page.getByRole('button', { name: 'Mobile' }).click()
await page.waitForTimeout(4000)
await shot(page, '05-preview-mobile-frame')
await page.getByRole('button', { name: 'All changes' }).click()
await settle(page)

await page.getByRole('button', { name: /From library/ }).click()
await settle(page)
await shot(page, '06-library')
await page.keyboard.press('Escape')

await page.getByRole('button', { name: /^Apply / }).click()
await page.getByRole('heading', { name: 'Applied' }).waitFor({ timeout: 20000 })
await settle(page)
await shot(page, '08-applied')

await page.setViewportSize({ width: 390, height: 844 })
await settle(page)
await shot(page, '07-mobile', { fullPage: true })

await browser.close()
