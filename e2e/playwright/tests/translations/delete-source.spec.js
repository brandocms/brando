import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'
import { e2eUrl } from '../../test-support/e2eUrl'

// Delete on the source of synchronized translations (#3926): a published
// English page, "Team", with a published Norwegian translation, "Laget"
// (E2EFixtureController :translated_page; pages synchronized, since they have
// a trash). The dialog asks what becomes of the translation; deleted with
// it, both go to the trash and come back together. The admin is in
// Norwegian, so the locators read its labels; the E2E setup hides the
// toasts, which are asserted by their level.

async function translatedPage(page, params = '') {
  const response = await page.request.post(`/e2e/translated-page${params}`)
  expect(response.ok(), await response.text()).toBe(true)
  return response.json()
}

test.beforeEach(async ({ page }) => {
  expect((await page.request.post('/e2e/synchronized-pages/on')).ok()).toBe(true)
  expect((await page.request.post('/e2e/setup_fixtures/admin-language-no')).ok()).toBe(true)
  await page.setViewportSize({ width: 1440, height: 1000 })
})

// Synchronized pages are application config, which outlives the test's sandbox.
test.afterEach(async ({ page }) => {
  expect((await page.request.post('/e2e/synchronized-pages/off')).ok()).toBe(true)
})

const pageRow = (page, title) =>
  page.locator('.list-row').filter({ has: page.getByRole('link', { name: title, exact: true }) })

async function openDelete(page, title) {
  const row = pageRow(page, title)
  await row.getByTestId('circle-dropdown-button').click()
  await row.getByRole('button', { name: 'Slett', exact: true }).click()
  const dialog = page.getByRole('dialog')
  await expect(dialog).toBeVisible()
  return dialog
}

test('deletes a source with its translation, and restoring the source brings both back', async ({ page }, testInfo) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await translatedPage(page)

  await page.goto('/admin/pages')
  await syncLV(page)

  const dialog = await openDelete(page, 'Team')
  await expect(dialog.getByText('Laget', { exact: true })).toBeVisible()
  await expect(dialog.getByRole('radio', { name: 'Slett dem med den' })).toBeChecked()
  await dialog.screenshot({ path: testInfo.outputPath('delete-source-dialog.png') })

  await dialog.getByRole('button', { name: 'Slett', exact: true }).click()
  await expect(dialog).toBeHidden()
  await expect(page.locator('.toast--success')).toHaveCount(1)
  await syncLV(page)
  await expect(pageRow(page, 'Team')).toHaveCount(0)

  // In the trash (the list shows the content language's); restored, the
  // source is back with its translation among its language versions. The
  // status filters patch the list in place: leaving the page would make the
  // presence tracker wait on the admin user, whom the setup changed.
  await page.getByRole('button', { name: /Slettet/ }).click()
  await syncLV(page)
  const trashed = page.locator('.list-row').filter({ hasText: 'Team' })
  await trashed.getByTestId('circle-dropdown-button').click()
  await trashed.getByRole('button', { name: 'Gjenopprett' }).click()
  await expect(page.locator('.toast--success')).toHaveCount(2)
  await syncLV(page)
  await expect(trashed).toHaveCount(0)

  await page.getByRole('button', { name: /Publisert/ }).click()
  await syncLV(page)
  await expect(pageRow(page, 'Team')).toHaveCount(1)
  await expect(pageRow(page, 'Team').getByRole('link', { name: /NO/ })).toHaveCount(1)

  expect(errors).toEqual([])
})

test('a translation in the trash stays there; keeping it makes it independent', async ({ page }, testInfo) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await translatedPage(page, '?trashed=true')

  await page.goto('/admin/pages')
  await syncLV(page)

  const dialog = await openDelete(page, 'Team')
  await expect(dialog.getByText('Laget', { exact: true })).toBeVisible()
  await dialog.screenshot({ path: testInfo.outputPath('delete-source-trashed-dialog.png') })

  await dialog.getByRole('radio', { name: 'Behold dem som selvstendige oppføringer' }).check()
  await dialog.getByRole('button', { name: 'Slett', exact: true }).click()
  await expect(dialog).toBeHidden()
  await expect(page.locator('.toast--success')).toHaveCount(1)
  await syncLV(page)
  await expect(pageRow(page, 'Team')).toHaveCount(0)

  expect(errors).toEqual([])
})

test.describe('someone who may not publish', () => {
  test.skip(process.env.BRANDO_AUTHORIZATION_MODE !== 'groups', 'Requires explicit group mode')

  test('is not offered to delete the published translation with it', async ({
    page,
    secondUserPage,
    sandboxUserAgent
  }, testInfo) => {
    // The source a draft, which this account may delete
    await translatedPage(page, '?source=draft')
    const grant = await fetch(e2eUrl('/e2e/authorization/page-deleter'), {
      method: 'POST',
      headers: { 'user-agent': sandboxUserAgent }
    })
    expect(grant.ok, await grant.text()).toBe(true)

    await secondUserPage.setViewportSize({ width: 1440, height: 1000 })
    await secondUserPage.goto('/admin/pages')
    await syncLV(secondUserPage)

    // This account's admin is in English
    const row = pageRow(secondUserPage, 'Team')
    await row.getByTestId('circle-dropdown-button').click()
    await row.getByRole('button', { name: 'Delete', exact: true }).click()
    const dialog = secondUserPage.getByRole('dialog')
    await expect(dialog).toBeVisible()
    await expect(dialog.getByRole('radio', { name: 'Delete them with it' })).toHaveCount(0)
    await expect(dialog.getByRole('radio', { name: 'Keep them as independent entries' })).toBeVisible()
    await dialog.screenshot({ path: testInfo.outputPath('delete-source-not-offered-dialog.png') })
    await dialog.getByRole('button', { name: 'Cancel' }).click()
    await expect(dialog).toBeHidden()
  })
})
