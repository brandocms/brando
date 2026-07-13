import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Regression guard for the post-save re-seed (the `replace_form` cascade).
//
// Blocks own their forms exclusively — after a save-and-continue, every
// mounted block component must be re-seeded with the freshly persisted data
// (new db ids). Without the re-seed, the next save diffs against stale
// nil-id state: nested rows (vars/refs/children) lose their identity and
// get duplicated or churned, and edits made after the first save can be
// lost. Other specs always save-then-navigate, which never exercises this.
test.describe('Save and continue editing', () => {
  test.setTimeout(90000)

  const saveAndContinue = async (page) => {
    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
    await syncLV(page)
    await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })
    // let the post-save replace_form re-seed land before further edits
    await page.waitForTimeout(750)
  }

  test('block edits survive repeated save-and-continue without duplication', async ({ page }) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill('Save Continue Test')
    await page.getByLabel('URI').fill('save-continue-test')

    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: 'Styled Header' }).click()
    await syncLV(page)

    const headerText = page.locator('.header-block textarea')
    await headerText.fill('First')
    await headerText.blur()
    await syncLV(page)

    await saveAndContinue(page)

    // exactly one block with one header ref after the first save
    await expect(page.locator('.entry-block')).toHaveCount(1)
    await expect(page.locator('.header-block textarea')).toHaveCount(1)
    await expect(page.locator('.header-block textarea')).toHaveValue('First')

    // edit in the SAME session — the component must now hold persisted ids
    await page.locator('.header-block textarea').fill('Edited after save')
    await page.locator('.header-block textarea').blur()
    await syncLV(page)

    await saveAndContinue(page)

    await expect(page.locator('.entry-block')).toHaveCount(1)
    await expect(page.locator('.header-block textarea')).toHaveCount(1)
    await expect(page.locator('.header-block textarea')).toHaveValue('Edited after save')

    // full reopen — the persisted state is the truth
    await page.goto('/admin/pages')
    await syncLV(page)
    await page.getByRole('link', { name: 'Save Continue Test →' }).click()
    await syncLV(page)

    await expect(page.locator('.entry-block')).toHaveCount(1)
    await expect(page.locator('.header-block textarea')).toHaveCount(1)
    await expect(page.locator('.header-block textarea')).toHaveValue('Edited after save')
  })
})
