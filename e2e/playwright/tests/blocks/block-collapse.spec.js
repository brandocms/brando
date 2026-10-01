import { test, expect } from '../../test-support/setupAuth'
import { serverLatency } from '../../test-support/latency'
import { syncLV } from '../../utils'

// Collapsing a block is a checkbox in its form. The block and the eye icon
// used to change only when the validate reply came back, which is instant on
// a local server and a visible lag on a real connection. Server frames are
// held back here, so the first half of each step passes only if the page
// changes on its own.
test.describe('Collapsing a block', () => {
  test.setTimeout(90000)

  const HELD_MS = 1500

  test('shows at once, before the server replies, and is saved', async ({ page }) => {
    const latency = await serverLatency(page)

    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill('Collapse Test')
    await page.getByLabel('URI').fill('collapse-test')

    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await expect(page.locator('.module-picker-namespace.active')).toContainText('05 LIVE PREVIEW TEST')
    await page.getByRole('button', { name: 'Styled Header' }).click()
    await syncLV(page)

    const block = page.locator('.base-block').first()
    const toggler = block.locator('.block-actions label.toggler').first()
    const content = block.locator('.header-block textarea')
    await expect(content).toBeVisible()
    await expect(toggler.locator('.when-expanded')).toBeVisible()
    await expect(toggler.locator('.when-collapsed')).toBeHidden()

    latency.set(HELD_MS)
    await toggler.click()
    await expect(block).toHaveClass(/\bcollapsed\b/, { timeout: 500 })
    await expect(content).toBeHidden({ timeout: 500 })
    await expect(toggler.locator('.when-collapsed')).toBeVisible({ timeout: 500 })
    await expect(toggler.locator('.when-expanded')).toBeHidden()

    // The held reply lands and agrees.
    latency.set(0)
    await syncLV(page)
    await expect(block).toHaveClass(/\bcollapsed\b/)

    latency.set(HELD_MS)
    await toggler.click()
    await expect(block).not.toHaveClass(/\bcollapsed\b/, { timeout: 500 })
    await expect(content).toBeVisible({ timeout: 500 })
    await expect(toggler.locator('.when-expanded')).toBeVisible({ timeout: 500 })

    latency.set(0)
    await syncLV(page)
    await expect(block).not.toHaveClass(/\bcollapsed\b/)

    // Collapse again and check the server kept it.
    await toggler.click()
    await syncLV(page)
    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
    await syncLV(page)

    await page.reload()
    await syncLV(page)
    await expect(block).toHaveClass(/\bcollapsed\b/)
    await expect(toggler.locator('.when-collapsed')).toBeVisible()
  })
})
