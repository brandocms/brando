import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test.describe('Entry revisions', () => {
  test.setTimeout(90000)

  test('stores, previews, and activates the current editor state including blocks', async ({ page }) => {
    await page.goto('/admin/pages')
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Revision base')
    await page.getByLabel('URI').fill('revision-system-test')
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: 'HEADERS' }).click()
    await page.getByRole('button', { name: 'Heading', exact: true }).click()
    await syncLV(page)

    await page.locator('.entry-block textarea').first().fill('Base block')
    await page.locator('.entry-block textarea').first().blur()

    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
    await syncLV(page)

    await page.getByLabel('Title', { exact: true }).fill('Revision working copy')
    await page.locator('.entry-block textarea').first().fill('Working-copy block')
    await page.locator('.entry-block textarea').first().blur()
    await syncLV(page)

    await page.getByRole('button', { name: 'Revisions' }).click()
    const drawer = page.locator('[id$="-revisions-drawer"]')
    await expect(drawer).toBeVisible()
    await drawer.getByRole('button', { name: 'Store current editor state' }).click()
    await expect(drawer.locator('#preview-revision-1')).toBeVisible({ timeout: 30000 })

    await drawer.getByRole('button', { name: 'Close' }).click()
    await page.getByLabel('Title', { exact: true }).fill('Discard this title')
    await page.locator('.entry-block textarea').first().fill('Discard this block')
    await page.locator('.entry-block textarea').first().blur()
    await syncLV(page)

    await page.getByRole('button', { name: 'Revisions' }).click()
    await drawer.locator('#preview-revision-1').click()
    await page.getByRole('button', { name: 'OK' }).click()

    await expect(page.getByLabel('Title', { exact: true })).toHaveValue('Revision working copy')
    await expect(page.locator('.entry-block textarea').first()).toHaveValue('Working-copy block')
    await expect(drawer.getByText('Revision 1 is loaded as an unsaved working copy.')).toBeVisible()

    const revisionRow = drawer.locator('#revision-line-1')
    await revisionRow.getByTestId('circle-dropdown-button').click()
    await revisionRow.getByRole('button', { name: 'Activate revision' }).click()
    await page.getByRole('button', { name: 'OK' }).click()

    await expect(page.getByLabel('Title', { exact: true })).toHaveValue('Revision working copy')
    await expect(page.locator('.entry-block textarea').first()).toHaveValue('Working-copy block')

    await page.reload()
    await syncLV(page)
    await expect(page.getByLabel('Title', { exact: true })).toHaveValue('Revision working copy')
    await expect(page.locator('.entry-block textarea').first()).toHaveValue('Working-copy block')
  })
})
