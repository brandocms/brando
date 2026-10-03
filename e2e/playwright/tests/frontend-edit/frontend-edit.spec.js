import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'
import { baseURL } from '../../test-support/e2eUrl'

// Frontend edit mode on a published page (E2EFixtureController `frontend-edit`):
// a "Headline" block, a container holding another, and an embedded shared
// fragment with one of its own. Screenshots of each state go to the test's
// output directory.

test.beforeEach(async ({ page }) => {
  const response = await page.request.post('/e2e/setup_fixtures/frontend-edit')
  expect(response.ok()).toBeTruthy()
  await page.setViewportSize({ width: 1440, height: 900 })
})

const shot = (page, name) => page.screenshot({ path: test.info().outputPath(`${name}.png`) })

const sidebar = page => page.frameLocator('[data-testid="frontend-edit-sidebar"] iframe')
const headline = (page, text) => page.locator('h2.fe-headline', { hasText: text })
const headlineInput = editor => editor.locator('.frontend-editor input[name$="[value]"]').first()

async function startEditing(page) {
  await page.goto('/frontend-edit')
  await page.getByTestId('frontend-edit-toggle').click()
  await expect(page.getByTestId('frontend-edit-toolbar')).toBeVisible()
}

async function openBlock(page, text) {
  await headline(page, text).click()
  const editor = sidebar(page)
  await expect(headlineInput(editor)).toHaveValue(text, { timeout: 15000 })
  return editor
}

async function adminUrl(editor) {
  const href = await editor.locator('.frontend-editor-open').getAttribute('href')
  return href.split('?')[0]
}

test('visitors get no editing, admins get a button that switches edit mode on', async ({ page, browser, sandboxUserAgent }) => {
  // Same sandbox, no session
  const visitor = await browser.newContext({ baseURL, userAgent: sandboxUserAgent })
  const anonymous = await visitor.newPage()
  await anonymous.goto('/frontend-edit')
  await expect(anonymous.locator('h2.fe-headline').first()).toBeVisible()
  await expect(anonymous.locator('brando-frontend-edit')).toHaveCount(0)
  expect(await anonymous.content()).not.toContain('[+:B<')
  await visitor.close()

  await page.goto('/frontend-edit')
  await expect(page.getByTestId('frontend-edit-toggle')).toBeVisible()
  expect(await page.content()).not.toContain('[+:B<')
  await shot(page, '00-toggle')

  await page.getByTestId('frontend-edit-toggle').click()
  await expect(page.getByTestId('frontend-edit-toolbar')).toBeVisible()
  expect(await page.content()).toContain('[+:B<')

  // Done switches it off again
  await page.getByTestId('frontend-edit-toolbar').getByRole('button').click()
  await expect(page.getByTestId('frontend-edit-toggle')).toBeVisible()
  expect(await page.content()).not.toContain('[+:B<')
})

test('an admin edits a block in place and saves it', async ({ page }) => {
  await startEditing(page)
  await shot(page, '01-edit-mode')

  await headline(page, 'Welcome to the page').hover()
  await shot(page, '02-hover')

  const editor = await openBlock(page, 'Welcome to the page')
  await shot(page, '03-sidebar')

  // Only the block: no entry fields, tabs or other blocks
  await expect(editor.locator('.form-tabs')).toHaveCount(0)
  await expect(editor.locator('.entry-block')).toHaveCount(1)

  await headlineInput(editor).fill('Edited from the website')
  await expect(headline(page, 'Edited from the website')).toBeVisible({ timeout: 10000 })
  await expect(editor.locator('.frontend-edit-status-dot')).toBeVisible()
  await shot(page, '04-live')

  await editor.getByTestId('submit').click()
  await expect(editor.locator('.frontend-edit-status .hero-check-circle-mini')).toBeVisible({ timeout: 15000 })
  await shot(page, '05-saved')

  await page.reload()
  await expect(headline(page, 'Edited from the website')).toBeVisible()
  await expect(headline(page, 'Inside the section')).toBeVisible()
})

test('a block in a container opens alone, and other blocks of the entry open in the same editor', async ({ page }) => {
  await startEditing(page)
  const editor = await openBlock(page, 'Inside the section')

  // The container is only the way down: none of its own settings show
  await expect(editor.locator('.base-block.focus-ancestor')).toHaveCount(1)
  await expect(editor.locator('.base-block.focus-ancestor > .block > form')).toBeHidden()
  await expect(editor.locator('.base-block.focus-target')).toHaveCount(1)
  await shot(page, '06-container-child')

  await headlineInput(editor).fill('Section, edited')
  await expect(headline(page, 'Section, edited')).toBeVisible({ timeout: 10000 })
  await editor.getByTestId('submit').click()
  await expect(editor.locator('.frontend-edit-status .hero-check-circle-mini')).toBeVisible({ timeout: 15000 })

  // Saved, so another block of the page opens at once
  await headline(page, 'Welcome to the page').click()
  await expect(headlineInput(editor)).toHaveValue('Welcome to the page', { timeout: 15000 })
  await expect(editor.locator('.base-block.focus-ancestor')).toHaveCount(0)
})

test('a shared fragment says where its changes show', async ({ page }) => {
  await startEditing(page)
  await headline(page, 'Shared notice text').hover()
  await shot(page, '07-fragment-hover')

  const editor = await openBlock(page, 'Shared notice text')
  await expect(editor.getByTestId('frontend-edit-shared')).toBeVisible()
  expect(await adminUrl(editor)).toContain('/admin/pages/fragments/update/')
  await shot(page, '08-fragment')

  await headlineInput(editor).fill('Shared notice, edited')
  await expect(headline(page, 'Shared notice, edited')).toBeVisible({ timeout: 10000 })
})

test('leaving a block with unsaved changes asks first', async ({ page }) => {
  await startEditing(page)
  const editor = await openBlock(page, 'Welcome to the page')
  await headlineInput(editor).fill('Not yet saved')
  await expect(headline(page, 'Not yet saved')).toBeVisible({ timeout: 10000 })

  // Keep editing
  await headline(page, 'Inside the section').click()
  const dialog = page.getByRole('alertdialog')
  await expect(dialog).toBeVisible()
  await shot(page, '09-unsaved')
  await dialog.locator('[data-action="keep"]').click()
  await expect(dialog).toBeHidden()
  await expect(headlineInput(editor)).toHaveValue('Not yet saved')

  // Save, then go on to the block that was clicked
  await headline(page, 'Inside the section').click()
  await dialog.locator('[data-action="save"]').click()
  await expect(headlineInput(editor)).toHaveValue('Inside the section', { timeout: 15000 })
  await page.reload()
  await expect(headline(page, 'Not yet saved')).toBeVisible()

  // Discard puts the page back and opens the clicked block
  const reopened = await openBlock(page, 'Not yet saved')
  await headlineInput(reopened).fill('Thrown away')
  await expect(headline(page, 'Thrown away')).toBeVisible({ timeout: 10000 })
  await headline(page, 'Inside the section').click()
  await dialog.locator('[data-action="discard"]').click()
  await expect(headline(page, 'Not yet saved')).toBeVisible({ timeout: 15000 })
  await expect(headlineInput(sidebar(page))).toHaveValue('Inside the section', { timeout: 15000 })
})

test('Escape and the close button close the sidebar', async ({ page }) => {
  await startEditing(page)
  await openBlock(page, 'Welcome to the page')
  await page.keyboard.press('Escape')
  await expect(page.getByTestId('frontend-edit-sidebar')).toHaveCount(0)

  const editor = await openBlock(page, 'Welcome to the page')
  await editor.locator('[data-frontend-edit-close]').click()
  await expect(page.getByTestId('frontend-edit-sidebar')).toHaveCount(0)
})

test('the admin form and the sidebar show each other, and a save elsewhere stops this one', async ({ page, secondUserPage }) => {
  await startEditing(page)
  const editor = await openBlock(page, 'Welcome to the page')
  const url = await adminUrl(editor)

  await secondUserPage.goto(url)
  await syncLV(secondUserPage)

  // The form shows someone editing from the website
  await expect(secondUserPage.locator('.page-presences .user-presence.is-frontend')).toBeVisible({ timeout: 10000 })
  // The sidebar shows someone in the admin
  await expect(editor.getByTestId('frontend-edit-presence')).toBeVisible({ timeout: 10000 })
  await shot(page, '10-presence')

  // They save; this editor may no longer save over them
  await secondUserPage.getByLabel('Title', { exact: true }).fill('Renamed in the admin')
  await secondUserPage.keyboard.press('Control+s')
  await expect(editor.getByTestId('frontend-edit-stale')).toBeVisible({ timeout: 15000 })
  await shot(page, '11-stale')

  await headlineInput(editor).fill('Over their save')
  await editor.getByTestId('submit').click()
  await expect(editor.locator('dialog[open], .alert-dialog, [role="alertdialog"]').first()).toBeVisible({ timeout: 10000 })
})

test('the full editor opens at the block', async ({ page }) => {
  await startEditing(page)
  const editor = await openBlock(page, 'Inside the section')
  const href = await editor.locator('.frontend-editor-open').getAttribute('href')
  const uid = new URL(href, 'http://x').searchParams.get('block')

  await page.goto(href)
  await syncLV(page)
  const block = page.locator(`#base-block-${uid}`)
  await expect(block).toHaveClass(/is-deep-linked/, { timeout: 15000 })
  await expect(block).toBeInViewport()
  expect(page.url()).not.toContain('block=')
})

test('an image chosen in the sidebar shows on the page and is saved', async ({ page }) => {
  test.setTimeout(90000)
  await startEditing(page)
  await page.locator('figure[b-tpl="single-image"] figcaption', { hasText: 'A picture caption' }).click()

  const editor = sidebar(page)
  const field = editor.locator('.picture-block .media-field--block:visible').first()
  await expect(field).toBeVisible({ timeout: 15000 })
  await field.locator('input[type="file"]').setInputFiles('./fixtures/image.jpg')

  // The upload may ask where to put it, or whether to keep a duplicate
  const uploadHere = editor.getByRole('button', { name: /^(Upload here|Last opp her)$/ })
  if (await uploadHere.waitFor({ state: 'visible', timeout: 3000 }).then(() => true).catch(() => false)) {
    await uploadHere.click()
  }
  const keep = editor.locator('#brando-upload-manager-lv').getByRole('button', { name: /^(Upload anyway|Last opp likevel)$/ })
  if (await keep.first().waitFor({ state: 'visible', timeout: 3000 }).then(() => true).catch(() => false)) {
    await keep.first().click()
  }

  await expect(field).toHaveAttribute('data-asset-id', /\d+/, { timeout: 30000 })
  const picture = page.locator('figure[b-tpl="single-image"] img')
  await expect(picture.first()).toBeAttached({ timeout: 15000 })
  await shot(page, '12-image')

  await editor.getByTestId('submit').click()
  await expect(editor.locator('.frontend-edit-status .hero-check-circle-mini')).toBeVisible({ timeout: 15000 })
  await page.reload()
  await expect(page.locator('figure[b-tpl="single-image"] img').first()).toBeAttached()
})

test('a Norwegian admin gets the editor in Norwegian', async ({ page }) => {
  const response = await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')
  expect(response.ok()).toBeTruthy()

  await page.goto('/frontend-edit')
  await page.getByRole('button', { name: 'Rediger side' }).click()
  const toolbar = page.getByTestId('frontend-edit-toolbar')
  await expect(toolbar.getByRole('button', { name: 'Ferdig' })).toBeVisible()

  const editor = await openBlock(page, 'Welcome to the page')
  await expect(editor.getByRole('button', { name: 'Lukk redigering' })).toBeVisible()
  await headlineInput(editor).fill('Endret på nettsiden')
  await expect(headline(page, 'Endret på nettsiden')).toBeVisible({ timeout: 10000 })

  await headline(page, 'Inside the section').click()
  const dialog = page.getByRole('alertdialog', { name: 'Ulagrede endringer' })
  await expect(dialog.getByRole('button', { name: 'Fortsett å redigere' })).toBeVisible()
  await expect(dialog.getByRole('button', { name: 'Forkast endringer' })).toBeVisible()
  await dialog.getByRole('button', { name: 'Lagre' }).click()
  await expect(headlineInput(editor)).toHaveValue('Inside the section', { timeout: 15000 })
  await expect(editor.getByRole('button', { name: /Lagre/ })).toBeVisible()
})

test('the toolbar and sidebar fit a phone', async ({ page }) => {
  await page.setViewportSize({ width: 390, height: 844 })
  await page.goto('/frontend-edit')
  await shot(page, '13-phone-toggle')
  await page.getByTestId('frontend-edit-toggle').click()

  const toolbar = page.getByTestId('frontend-edit-toolbar')
  await expect(toolbar).toBeInViewport({ ratio: 1 })

  const editor = await openBlock(page, 'Welcome to the page')
  const box = await page.getByTestId('frontend-edit-sidebar').boundingBox()
  expect(box.width).toBeLessThanOrEqual(390)
  expect(await editor.locator('body').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
  await expect(editor.getByTestId('submit')).toBeInViewport()
  await shot(page, '14-phone-sidebar')
})
