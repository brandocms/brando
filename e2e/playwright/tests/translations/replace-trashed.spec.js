import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// An English page whose Norwegian translation is in the trash
// (E2EFixtureController :trashed_page_translation; pages synchronized, since
// they have a trash). Creating the Norwegian translation again asks first:
// Cancel changes nothing, and confirming deletes the version in the trash for
// good and opens the new one (#3762). The admin is in Norwegian, so the
// locators read its labels.

let sourceId, targetId

test.beforeEach(async ({ page }) => {
  expect((await page.request.post('/e2e/synchronized-pages/on')).ok()).toBe(true)
  expect((await page.request.post('/e2e/setup_fixtures/admin-language-no')).ok()).toBe(true)
  const response = await page.request.post('/e2e/trashed-page-translation')
  expect(response.ok(), await response.text()).toBe(true)
  ;({ source_id: sourceId, target_id: targetId } = await response.json())
  await page.setViewportSize({ width: 1440, height: 1000 })
})

// Synchronized pages are application config, which outlives the test's sandbox.
test.afterEach(async ({ page }) => {
  expect((await page.request.post('/e2e/synchronized-pages/off')).ok()).toBe(true)
})

test('the form asks before replacing the translation in the trash; Cancel changes nothing', async ({ page }, testInfo) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))

  await page.goto(`/admin/pages/update/${sourceId}`)
  await syncLV(page)

  const create = page.locator('.translation-create').getByRole('button', { name: 'Norsk' })
  await create.click()

  const dialog = page.getByRole('dialog')
  await expect(dialog).toBeVisible()
  await dialog.screenshot({ path: testInfo.outputPath('replace-trashed-dialog.png') })
  await dialog.getByRole('button', { name: 'Avbryt' }).click()
  await expect(dialog).toBeHidden()
  await syncLV(page)
  // Nothing was sent: still on the source, with the language still offered
  await expect(page).toHaveURL(new RegExp(`/admin/pages/update/${sourceId}$`))
  await expect(create).toHaveCount(1)

  await create.click()
  await expect(dialog).toBeVisible()
  await dialog.getByRole('button', { name: 'Slett og opprett' }).click()

  await expect(page).not.toHaveURL(new RegExp(`/admin/pages/update/${sourceId}$`), { timeout: 10000 })
  await expect(page).not.toHaveURL(new RegExp(`/admin/pages/update/${targetId}$`))
  await expect(page.locator('#translation-panel')).toBeVisible({ timeout: 10000 })

  expect(errors).toEqual([])
})

test('the listing asks before replacing the translation in the trash, and opens the new one', async ({ page }) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))

  await page.goto('/admin/pages')
  await syncLV(page)

  const row = page.locator('.list-row').filter({ has: page.getByRole('link', { name: 'About us', exact: true }) })
  await row.getByTestId('circle-dropdown-button').click()
  await row.getByRole('button', { name: /Opprett oversettelse \[NO\]/ }).click()

  const dialog = page.getByRole('dialog')
  await expect(dialog).toBeVisible()
  await dialog.getByRole('button', { name: 'Slett og opprett' }).click()

  await expect(page).toHaveURL(/\/admin\/pages\/update\/\d+$/, { timeout: 10000 })
  await expect(page).not.toHaveURL(new RegExp(`/admin/pages/update/(${sourceId}|${targetId})$`))
  await syncLV(page)
  await expect(page.locator('#translation-panel')).toBeVisible()

  expect(errors).toEqual([])
})
