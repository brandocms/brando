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

    await page.getByRole('button', { name: 'History', exact: true }).click()
    const drawer = page.locator('[id$="-revisions-drawer"]')
    await expect(drawer).toBeVisible()
    await drawer.getByRole('tab', { name: /Revisions/ }).click()
    await drawer.getByRole('button', { name: 'Store current editor state' }).click()
    await expect(drawer.locator('#preview-revision-1')).toBeVisible({ timeout: 30000 })

    await drawer.getByRole('button', { name: 'Close' }).click()
    await page.getByLabel('Title', { exact: true }).fill('Discard this title')
    await page.locator('.entry-block textarea').first().fill('Discard this block')
    await page.locator('.entry-block textarea').first().blur()
    await syncLV(page)

    await page.getByRole('button', { name: 'History', exact: true }).click()
    await drawer.getByRole('tab', { name: /Revisions/ }).click()
    await drawer.locator('#preview-revision-1').click()
    await page.getByRole('button', { name: 'OK' }).click()

    await expect(page.getByLabel('Title', { exact: true })).toHaveValue('Revision working copy')
    await expect(page.locator('.entry-block textarea').first()).toHaveValue('Working-copy block')
    await expect(drawer.getByText('Revision 1 is loaded as an unsaved working copy.')).toBeVisible()

    const revisionRow = drawer.locator('#revision-line-1')
    await revisionRow.getByTestId('circle-dropdown-button').click()
    await revisionRow.getByRole('button', { name: 'Activate revision' }).click()
    await page.getByRole('button', { name: 'OK' }).click()
    // The editor already shows the working copy, so its values can't tell
    // whether the activation reached the server. The row turning active can;
    // reloading before then reads the entry as it was.
    await expect(revisionRow).toHaveClass(/\bactive\b/)
    await syncLV(page)

    await expect(page.getByLabel('Title', { exact: true })).toHaveValue('Revision working copy')
    await expect(page.locator('.entry-block textarea').first()).toHaveValue('Working-copy block')

    await page.reload()
    await syncLV(page)
    await expect(page.getByLabel('Title', { exact: true })).toHaveValue('Revision working copy')
    await expect(page.locator('.entry-block textarea').first()).toHaveValue('Working-copy block')
  })

  // A revision loaded as a working copy is unsaved changes to the entry as
  // it is now: saving it writes them. It used to become the form's data, so
  // Save wrote nothing and a reload showed the entry as it was.
  test('saving a revision loaded as a working copy writes it', async ({ page }) => {
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill('Revision kept')
    await page.getByLabel('URI').fill('revision-save-working-copy')
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: 'HEADERS' }).click()
    await page.getByRole('button', { name: 'Heading', exact: true }).click()
    await syncLV(page)
    await page.locator('.entry-block textarea').first().fill('Revision block')
    await page.locator('.entry-block textarea').first().blur()

    const save = async () => {
      await page.getByTestId('split-dropdown-button').click()
      await page.getByRole('button', { name: /Save and continue editing/ }).click()
    }

    await save()
    await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
    await syncLV(page)

    // revision 1 is the entry as saved
    await page.getByRole('button', { name: 'History', exact: true }).click()
    const drawer = page.locator('[id$="-revisions-drawer"]')
    await drawer.getByRole('tab', { name: /Revisions/ }).click()
    await drawer.getByRole('button', { name: 'Store current editor state' }).click()
    await expect(drawer.locator('#preview-revision-1')).toBeVisible({ timeout: 30000 })
    await drawer.getByRole('button', { name: 'Close' }).click()

    // the entry moves on, saved
    await page.getByLabel('Title', { exact: true }).fill('Moved on')
    await page.locator('.entry-block textarea').first().fill('Moved-on block')
    await page.locator('.entry-block textarea').first().blur()
    await syncLV(page)
    await save()
    await expect(page.locator('.draft-save-state').first()).toHaveAttribute('data-state', 'clean', { timeout: 15000 })
    await page.reload()
    await syncLV(page)
    await expect(page.getByLabel('Title', { exact: true })).toHaveValue('Moved on')
    await expect(page.locator('.entry-block textarea').first()).toHaveValue('Moved-on block')

    // revision 1, loaded and saved
    await page.getByRole('button', { name: 'History', exact: true }).click()
    await drawer.getByRole('tab', { name: /Revisions/ }).click()
    await drawer.locator('#preview-revision-1').click()
    await page.getByRole('button', { name: 'OK' }).click()
    await expect(page.getByLabel('Title', { exact: true })).toHaveValue('Revision kept')
    await expect(page.locator('.entry-block textarea').first()).toHaveValue('Revision block')
    await expect(page.locator('.draft-save-state').first()).toHaveAttribute('data-state', 'dirty')
    await drawer.getByRole('button', { name: 'Close' }).click()

    await save()
    await expect(page.locator('.draft-save-state').first()).toHaveAttribute('data-state', 'clean', { timeout: 15000 })
    await page.reload()
    await syncLV(page)
    await expect(page.getByLabel('Title', { exact: true })).toHaveValue('Revision kept')
    await expect(page.locator('.entry-block textarea').first()).toHaveValue('Revision block')
  })
})
