import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'

test.describe('Activity log', () => {
  test.setTimeout(90000)

  test('records saves, shows them in the entry history and compares revisions', async ({ page }, testInfo) => {
    await page.setViewportSize({ width: 1440, height: 900 })
    await page.goto('/admin/pages')
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Activity base')
    await page.getByLabel('URI').fill('activity-log-test')
    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Activity renamed')
    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await syncLV(page)

    await page.getByRole('button', { name: 'History', exact: true }).click()
    const drawer = page.locator('[id$="-revisions-drawer"]')
    await expect(drawer.getByRole('tab', { name: 'Activity' })).toHaveAttribute('aria-selected', 'true')

    const timeline = drawer.locator('.activity-timeline')
    await expect(timeline.locator('li')).toHaveCount(2)
    await expect(timeline.locator('li').first().locator('.activity-action')).toHaveText('Updated')
    await expect(timeline.locator('li').last().locator('.activity-action')).toHaveText('Created')

    await timeline.locator('li').first().getByRole('button', { name: /Compare with/ }).click()
    const comparison = drawer.locator('.activity-compare')
    await expect(comparison).toContainText('Activity base')
    await expect(comparison).toContainText('Activity renamed')
    await page.screenshot({ path: testInfo.outputPath('entry-history-compare.png') })

    await drawer.getByRole('button', { name: /All activity/ }).click()
    await expect(timeline).toBeVisible()
    await page.screenshot({ path: testInfo.outputPath('entry-history-desktop.png') })

    await page.goto('/admin/config/activity')
    await syncLV(page)

    const rows = page.locator('.activity-row')
    await expect(rows).toHaveCount(2)
    await expect(rows.first().locator('a.activity-entry')).toHaveText('Activity renamed')
    await expect(rows.first().locator('.activity-person-name')).toHaveText('Brando Admin')

    await page.locator('#activity-filters select[name=action]').selectOption('created')
    await expect(page).toHaveURL(/action=created/)
    await expect(rows).toHaveCount(1)
    await expect(rows.first().locator('.activity-action')).toHaveText('Created')

    await page.locator('#activity-filters select[name=action]').selectOption('')
    await expect(rows).toHaveCount(2)
    await rows.first().getByRole('button', { name: 'Compare' }).click()
    const modal = page.locator('#activity-compare-modal')
    await expect(modal).toBeVisible()
    await expect(modal.locator('.activity-compare')).toContainText('Activity renamed')
    await page.screenshot({ path: testInfo.outputPath('activity-compare.png') })
    await modal.getByRole('button', { name: 'Close dialog' }).click()
    await expect(modal).not.toBeVisible()

    await page.screenshot({ path: testInfo.outputPath('activity-desktop.png'), fullPage: true })
    await page.setViewportSize({ width: 390, height: 844 })
    await page.waitForTimeout(350)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    await page.screenshot({ path: testInfo.outputPath('activity-mobile.png'), fullPage: true })
  })
})
