import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test.describe('Block Recovery', () => {
  test.setTimeout(60000)

  test('blocks recover after disconnect/reconnect without errors', async ({ page }) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Block Recovery Test Page')
    await page.getByLabel('URI').fill('block-recovery-test')

    // Add a header block
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Styled Header' }).click()
    await syncLV(page)

    // Edit the header text to a known value
    const headerTextarea = page.locator('.header-block textarea')
    await headerTextarea.fill('Recovery Test Header')
    await syncLV(page)

    // Verify block is visible
    await expect(page.locator('.entry-block')).toHaveCount(1)

    // Disconnect and reconnect the LiveSocket
    await page.evaluate(() => window.liveSocket.disconnect())
    await page.waitForTimeout(500)
    await page.evaluate(() => window.liveSocket.connect())
    await syncLV(page)

    // Verify block is still present after reconnect
    await expect(page.locator('.entry-block')).toHaveCount(1)

    // Verify the header text survived the reconnect
    await expect(page.locator('.header-block textarea')).toHaveValue('Recovery Test Header')
  })

  test('stale sessionStorage does not trigger recovery on fresh navigation', async ({ page }) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Stale Recovery Test Page')
    await page.getByLabel('URI').fill('stale-recovery-test')

    // Add a header block
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Styled Header' }).click()
    await syncLV(page)

    // Simulate stale sessionStorage by disconnecting (which captures form data)
    // then navigating away without reconnecting
    await page.evaluate(() => window.liveSocket.disconnect())
    await page.waitForTimeout(300)

    // Navigate away and back — this is a fresh mount, not a reconnect
    await page.evaluate(() => window.liveSocket.connect())
    await page.goto('/admin')
    await syncLV(page)

    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)

    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Fresh Page After Stale')
    await page.getByLabel('URI').fill('fresh-after-stale')

    // Add a block — this should work without any "already associated" errors
    await page.getByRole('button', { name: 'Add block' }).click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Styled Header' }).click()
    await syncLV(page)

    // Verify the block rendered correctly (no crash)
    await expect(page.locator('.entry-block')).toHaveCount(1)
    await expect(page.locator('.header-block textarea')).toBeVisible()
  })
})
