import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Names, filenames and colour values other admins control reach this admin's
// page through alerts, tooltips, the colour picker and the progress panel.
// Each must show as text. The value below is markup whose image fails to
// load; if a page parsed it, its error handler would mark the document.
const MARKUP = '<img src="data:," onerror="document.documentElement.dataset.sinkRan=1">Ada'

const ran = root => root.locator('html').getAttribute('data-sink-ran')

async function renameEditor(page, name) {
  const response = await page.request.post('/e2e/text-sinks/user-name', {
    data: { email: 'editor@brandocms.com', name }
  })
  expect(response.ok()).toBeTruthy()
}

test("a presence tooltip shows the other editor's name as text", async ({ page, secondUserPage }) => {
  await renameEditor(page, MARKUP)

  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  await secondUserPage.goto('/admin/pages/update/1')
  await syncLV(secondUserPage)

  await secondUserPage.getByLabel('Title', { exact: true }).click()
  const avatar = page.locator('.field-wrapper.field-locked .field-presence-user .avatar')
  await expect(avatar).toHaveCount(1)

  await avatar.hover()
  const tooltip = page.locator('.tippy-content')
  await expect(tooltip).toContainText(MARKUP)
  await expect(tooltip.locator('img')).toHaveCount(0)
  expect(await ran(page)).toBeNull()
})

test('the colour picker shows a stored colour value as text', async ({ page }) => {
  const response = await page.request.post('/e2e/text-sinks/color-image', { data: { color: MARKUP } })
  expect(response.ok()).toBeTruthy()
  const { id } = await response.json()

  await page.goto(`/admin/assets/images/update/${id}`)
  await syncLV(page)

  const hex = page.locator('[phx-hook="Brando.ColorPicker"] .color-hex')
  await expect(hex).toHaveText(MARKUP)
  await expect(hex.locator('img')).toHaveCount(0)
  expect(await ran(page)).toBeNull()
})

test('the progress panel and popup show filenames and messages as text', async ({ page }) => {
  const joined = page.waitForEvent('console', msg => msg.text().includes('Joined user_channel'))
  await page.goto('/admin')
  await syncLV(page)
  await joined

  const response = await page.request.post('/e2e/text-sinks/progress', {
    data: { key: 'text-sinks', filename: MARKUP, status: `Status ${MARKUP}`, popup: `Popup ${MARKUP}` }
  })
  expect(response.ok()).toBeTruthy()

  const item = page.locator('.progress-item[data-progress-key="text-sinks"]')
  await expect(item.locator('.filename')).toHaveText(MARKUP)
  await expect(item.locator('.description')).toHaveText(`Status ${MARKUP}`)
  await expect(item.locator('.percent')).toHaveText('10%')
  await expect(page.locator('.progress-popup .message')).toHaveText(`[1] → Popup ${MARKUP}`)
  await expect(page.locator('.progress-item img, .progress-popup img')).toHaveCount(0)
  expect(await ran(page)).toBeNull()
})

test("the frontend editor's 'Not saved' alert shows the other user's name as text", async ({ page, secondUserPage }) => {
  const fixture = await page.request.post('/e2e/setup_fixtures/frontend-edit')
  expect(fixture.ok()).toBeTruthy()
  await renameEditor(page, MARKUP)

  await page.goto('/frontend-edit')
  await page.getByTestId('frontend-edit-toggle').click()
  await page.locator('h2.fe-headline', { hasText: 'Welcome to the page' }).click()
  const editor = page.frameLocator('[data-testid="frontend-edit-sidebar"] iframe')
  const headline = editor.locator('.frontend-editor input[name$="[value]"]').first()
  await expect(headline).toHaveValue('Welcome to the page', { timeout: 15000 })
  const url = (await editor.locator('.frontend-editor-open').getAttribute('href')).split('?')[0]

  // The other user saves the entry, so this editor's save is refused
  await secondUserPage.goto(url)
  await syncLV(secondUserPage)
  await secondUserPage.getByLabel('Title', { exact: true }).fill('Renamed in the admin')
  await secondUserPage.keyboard.press('Control+s')
  await expect(editor.getByTestId('frontend-edit-stale')).toBeVisible({ timeout: 15000 })

  await headline.fill('Over their save')
  await editor.getByTestId('submit').click()
  const dialog = editor.locator('dialog.admin-dialog[open]')
  await expect(dialog.locator('.admin-dialog-body')).toContainText(MARKUP)
  await expect(dialog.locator('img')).toHaveCount(0)
  expect(await ran(editor)).toBeNull()
  expect(await ran(page)).toBeNull()
})
