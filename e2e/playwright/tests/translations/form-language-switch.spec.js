import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// In an entry's form, the content language switch at the foot of the sidebar
// is on the entry's language, and a language opens the entry's version in it
// (ContentLanguageSwitch): an existing version, a new translation on a
// synchronized type (E2EFixtureController :synchronized_translation), or, on a
// type that is not synchronized, nothing but a note that there is none.

const switcher = page => page.locator('.content-language-selector')
const options = page => page.locator('#content-language-options')
const option = (page, name) => options(page).getByRole('option', { name: new RegExp(`^${name}`) })

async function openSwitch(page) {
  await page.locator('#content-language-trigger').click()
  await expect(options(page)).toBeVisible()
}

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

async function articles(page, data = {}) {
  const response = await page.request.post('/e2e/synchronized-translation', { data })
  expect(response.ok()).toBeTruthy()
  return response.json()
}

test.beforeEach(async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
})

test('opens the version in the language picked', async ({ page }, testInfo) => {
  const { source_id: sourceId, target_id: targetId } = await articles(page)

  await page.goto(`/admin/sync_test/articles/update/${sourceId}`)
  await syncLV(page)
  await openSwitch(page)

  // On the entry's language, Norwegian
  await expect(option(page, 'Norsk')).toHaveAttribute('aria-selected', 'true')
  await expect(option(page, 'English')).toHaveAttribute('aria-selected', 'false')
  await switcher(page).screenshot({ path: testInfo.outputPath('switch-version.png') })

  await option(page, 'English').click()
  await expect(page).toHaveURL(new RegExp(`/update/${targetId}$`))
  await syncLV(page)

  await openSwitch(page)
  await expect(option(page, 'English')).toHaveAttribute('aria-selected', 'true')
})

test('asks about unsaved changes, and staying keeps the form on its language', async ({ page }) => {
  const { source_id: sourceId } = await articles(page)

  await page.goto(`/admin/sync_test/articles/update/${sourceId}`)
  await syncLV(page)
  await openSwitch(page)

  // Offline, the edit stays out of recovery storage
  await page.evaluate(() => window.liveSocket.disconnect())
  const title = page.locator('input[name$="[title]"]').first()
  await title.fill('Ulagret tittel')

  const dialogPromise = page.waitForEvent('dialog')
  const click = option(page, 'English').click()
  const dialog = await dialogPromise
  await dialog.dismiss()
  await click

  await expect(page).toHaveURL(new RegExp(`/update/${sourceId}$`))
  await expect(title).toHaveValue('Ulagret tittel')
  await expect(option(page, 'Norsk')).toHaveAttribute('aria-selected', 'true')
  await page.evaluate(() => window.liveSocket.connect())
  await syncLV(page)
})

test('a synchronized type creates the translation of a language without one', async ({ page }, testInfo) => {
  const { source_id: sourceId } = await articles(page, { source_only: 'true' })

  await page.goto(`/admin/sync_test/articles/update/${sourceId}`)
  await syncLV(page)
  await openSwitch(page)
  await expect(option(page, 'English')).toBeEnabled()
  await switcher(page).screenshot({ path: testInfo.outputPath('switch-create.png') })

  await option(page, 'English').click()
  await expect(page).not.toHaveURL(new RegExp(`/update/${sourceId}$`))
  await expect(page.locator('#translation-panel')).toBeVisible({ timeout: 10000 })
  await syncLV(page)

  await openSwitch(page)
  await expect(option(page, 'English')).toHaveAttribute('aria-selected', 'true')
  await expect(option(page, 'Norsk')).toBeEnabled()
})

test('a type that is not synchronized says a language has no version, and stays', async ({ page }, testInfo) => {
  const client = await factory(page, 'E2eProject.Projects.Client', {
    name: 'Switch owner', slug: 'switch-owner', status: 'published', language: 'no',
  })
  const project = await factory(page, 'E2eProject.Projects.Project', {
    client_id: client.id, introduction: '<p>Intro</p>', language: 'no', title: 'Bare norsk', slug: 'bare-norsk', status: 'published',
  })

  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)
  await openSwitch(page)

  await expect(option(page, 'Norsk')).toHaveAttribute('aria-selected', 'true')
  await expect(option(page, 'English')).toBeDisabled()
  await switcher(page).screenshot({ path: testInfo.outputPath('switch-none.png') })
  await expect(page).toHaveURL(new RegExp(`/update/${project.id}$`))
})
