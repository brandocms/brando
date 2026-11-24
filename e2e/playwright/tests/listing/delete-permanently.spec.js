import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Delete permanently in a listing's trash (#3927): two cases in the trash
// (E2EFixtureController :trashed_projects), one that nothing refers to and
// one a category row still refers to. The admin is in Norwegian, so the
// locators read its labels.

test.beforeEach(async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/admin-language-no')).ok()).toBe(true)
  const response = await page.request.post('/e2e/trashed-projects')
  expect(response.ok(), await response.text()).toBe(true)
  await page.setViewportSize({ width: 1440, height: 1000 })
})

const trashRow = (page, title) => page.locator('.list-row').filter({ hasText: title })

async function deletePermanently(page, title, testInfo) {
  const row = trashRow(page, title)
  await row.getByTestId('circle-dropdown-button').click()
  await expect(row.getByRole('button', { name: 'Slett', exact: true })).toHaveCount(0)
  await row.getByRole('button', { name: 'Slett for godt' }).click()

  const dialog = page.getByRole('dialog')
  await expect(dialog).toBeVisible()
  if (testInfo) await dialog.screenshot({ path: testInfo.outputPath('delete-permanently-dialog.png') })
  await dialog.getByRole('button', { name: 'Slett for godt' }).click()
  await expect(dialog).toBeHidden()
}

test('deletes a case in the trash for good, and refuses one something refers to', async ({ page }, testInfo) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))

  await page.goto('/admin/projects?status=deleted')
  await syncLV(page)
  await expect(trashRow(page, 'Old case')).toHaveCount(1)

  await deletePermanently(page, 'Old case', testInfo)
  await expect(trashRow(page, 'Old case')).toHaveCount(0)
  await expect(page.locator('.toast--success')).toHaveCount(1)

  await deletePermanently(page, 'Categorised case')
  const refused = page.locator('.toast--error')
  await expect(refused).toHaveCount(1)
  await refused.screenshot({ path: testInfo.outputPath('delete-permanently-refused.png') })
  await syncLV(page)
  await expect(trashRow(page, 'Categorised case')).toHaveCount(1)

  expect(errors).toEqual([])
})
