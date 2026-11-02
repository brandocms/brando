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
  await expect(editor.locator('.frontend-edit-status .lucide-circle-check')).toBeVisible({ timeout: 15000 })
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
  await expect(editor.locator('.frontend-edit-status .lucide-circle-check')).toBeVisible({ timeout: 15000 })

  // Saved, so another block of the page opens at once
  await headline(page, 'Welcome to the page').click()
  await expect(headlineInput(editor)).toHaveValue('Welcome to the page', { timeout: 15000 })
  await expect(editor.locator('.base-block.focus-ancestor')).toHaveCount(0)
})

// A shared fragment's notice and full-editor link: frontend_edit_live_test.exs

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
  await expect(editor.locator('.frontend-edit-status .lucide-circle-check')).toBeVisible({ timeout: 15000 })
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

  // The open sidebar stops above the toolbar, so Done stays in reach: in the
  // viewport, and the element a click there lands on (a trial click fails if
  // the sidebar covers it). On a tablet too, where the two met.
  const done = toolbar.locator('.fe-toolbar-done')
  await expect(done).toBeInViewport({ ratio: 1 })
  await done.click({ trial: true, timeout: 2000 })
  await shot(page, '14-phone-sidebar')

  await page.setViewportSize({ width: 768, height: 1024 })
  await expect(done).toBeInViewport({ ratio: 1 })
  await done.click({ trial: true, timeout: 2000 })
  await expect(editor.getByTestId('submit')).toBeInViewport()
})

test.describe('entry fields', () => {
  const titleField = page => page.locator('h1.fe-page-title')
  const titleInput = editor => editor.locator('.frontend-editor input[name="page[title]"]')

  test('a title printed in the template and in a block is edited in both places', async ({ page }) => {
    await startEditing(page)
    await titleField(page).hover()
    await shot(page, '15-field-hover')
    await titleField(page).click()

    const editor = sidebar(page)
    await expect(titleInput(editor)).toHaveValue('Frontend edit', { timeout: 15000 })
    await expect(editor.locator('.frontend-editor-heading h1')).toHaveText('Title')
    await expect(editor.locator('.entry-block')).toHaveCount(0)
    await shot(page, '16-field-sidebar')

    await titleInput(editor).fill('Edited title')
    // The HEEx component at once, the Liquid tag in a block with the next render
    await expect(titleField(page)).toHaveText('Edited title', { timeout: 10000 })
    await expect(page.locator('p.fe-block-title')).toHaveText('On Edited title', { timeout: 10000 })

    await editor.getByTestId('submit').click()
    await expect(editor.locator('.frontend-edit-status .lucide-circle-check')).toBeVisible({ timeout: 15000 })

    await page.reload()
    await expect(titleField(page)).toHaveText('Edited title')
    await expect(page.locator('p.fe-block-title')).toHaveText('On Edited title')

    // The Liquid tag opens the same field. The paragraph is full width, and
    // only its text is the field; the rest of it opens the block. The page is
    // too short to scroll, and at the foot of the viewport the fixed toolbar
    // covers the paragraph, so give it room.
    await page.setViewportSize({ width: page.viewportSize().width, height: 1200 })
    await page.locator('p.fe-block-title').click({ position: { x: 50, y: 8 } })
    await expect(titleInput(sidebar(page))).toHaveValue('Edited title', { timeout: 15000 })
  })

  test('rich text and an image field open from the project page', async ({ page }) => {
    await page.goto('/project/test-project-alpha')
    await page.getByTestId('frontend-edit-toggle').click()
    await expect(page.getByTestId('frontend-edit-toolbar')).toBeVisible()

    await page.locator('.project-introduction p').click()
    const editor = sidebar(page)
    await expect(editor.locator('.frontend-editor-heading h1')).toHaveText('Introduction', { timeout: 15000 })
    await expect(editor.locator('.frontend-editor [data-testid], .frontend-editor .tiptap-wrapper, .frontend-editor [phx-hook="Brando.TipTap"]').first()).toBeAttached()
    await shot(page, '17-rich-text')

    // The picture is wrapped markup: after replacing it and saving, the page
    // shows what was saved
    const picture = page.locator('.project-header picture').first()
    const before = await picture.innerHTML()
    await picture.click()
    await expect(editor.locator('.frontend-editor-heading h1')).toHaveText('Listing image', { timeout: 15000 })
    await shot(page, '18-image-field')

    const field = editor.locator('.frontend-editor .media-field').first()
    const previousId = await field.getAttribute('data-asset-id')
    await field.locator('input[type="file"]').setInputFiles('./fixtures/image.jpg')
    const uploadHere = editor.getByRole('button', { name: /^(Upload here|Last opp her)$/ })
    if (await uploadHere.waitFor({ state: 'visible', timeout: 3000 }).then(() => true).catch(() => false)) {
      await uploadHere.click()
    }
    const keep = editor.locator('#brando-upload-manager-lv').getByRole('button', { name: /^(Upload anyway|Last opp likevel)$/ })
    if (await keep.first().waitFor({ state: 'visible', timeout: 3000 }).then(() => true).catch(() => false)) {
      await keep.first().click()
    }
    await expect(field).not.toHaveAttribute('data-asset-id', previousId || '', { timeout: 30000 })

    await editor.getByTestId('submit').click()
    await expect(editor.locator('.frontend-edit-status .lucide-circle-check')).toBeVisible({ timeout: 15000 })
    await expect.poll(() => page.locator('.project-header picture').first().innerHTML(), { timeout: 10000 }).not.toBe(before)
  })

  test('the full editor opens at the field', async ({ page }) => {
    await startEditing(page)
    await titleField(page).click()
    const editor = sidebar(page)
    await expect(titleInput(editor)).toBeVisible({ timeout: 15000 })
    const href = await editor.locator('.frontend-editor-open').getAttribute('href')
    expect(href).toContain('?field=title')

    await page.goto(href)
    await syncLV(page)
    const wrapper = page.locator('form.main-form .field-wrapper:has(input[name="page[title]"])')
    await expect(wrapper).toHaveClass(/is-deep-linked/, { timeout: 15000 })
    expect(page.url()).not.toContain('field=')
  })
})

test('a listing of selected entries gets a new selection', async ({ page }) => {
  await startEditing(page)
  const listing = page.locator('section[b-tpl="featured-projects"]')
  await expect(listing.locator('.project')).toHaveText(['Test Project Alpha'])
  await listing.locator('.project').first().click()

  const editor = sidebar(page)
  const selected = editor.locator('.module-datasource-selected .selected-entries .identifier')
  await expect(selected).toHaveCount(1, { timeout: 15000 })

  await editor.getByRole('button', { name: /^(Select entries|Velg oppføringer|Velg innlegg)$/ }).click()
  await editor.locator('.identifier').filter({ hasText: 'Test Project Beta' }).click()
  await editor.locator('[id^="select-entries-"] .modal-close').click()
  await expect(selected).toHaveCount(2)
  // The page lists the new selection before it is saved
  await expect(listing.locator('.project')).toHaveText(['Test Project Alpha', 'Test Project Beta'], { timeout: 10000 })
  await shot(page, '19-selection')

  await editor.getByTestId('submit').click()
  await expect(editor.locator('.frontend-edit-status .lucide-circle-check')).toBeVisible({ timeout: 15000 })
  await page.reload()
  await expect(listing.locator('.project')).toHaveText(['Test Project Alpha', 'Test Project Beta'])
})

test.describe('page content standing in for the configuration', () => {
  // What the look-alikes' editor address sets the title to if it ever runs
  const RAN = 'planted-config-ran'
  const iframe = page => page.locator('[data-testid="frontend-edit-sidebar"] iframe')

  // Serves the page changed by `transform`, for what the sanitizer would not
  // let through or the plug would not send.
  const rewritePage = (page, transform) =>
    page.route(/\/\/[^/]+\/frontend-edit$/, async route => {
      const response = await route.fetch()
      await route.fulfill({ response, body: transform(await response.text()) })
    })

  test('rich text cannot replace it, and the admin still edits the page', async ({ page }) => {
    await startEditing(page)

    const planted = await page.request.post('/e2e/setup_fixtures/frontend-edit-planted')
    expect(planted.ok()).toBeTruthy()
    await page.reload()

    // The sanitizer kept them, and they come before the plug's
    await expect(page.locator('p#brando-frontend-edit-config')).toHaveCount(1)
    await expect(page.locator('a#brando-frontend-edit-config')).toHaveCount(1)
    await expect(page.locator('img[name="currentScript"]')).toHaveCount(1)

    await expect(page.getByTestId('frontend-edit-toolbar')).toBeVisible()

    await headline(page, 'Welcome to the page').click()
    await expect(iframe(page)).toHaveAttribute('src', /^\/admin\/frontend-edit\?uid=/)
    await expect(headlineInput(sidebar(page))).toHaveValue('Welcome to the page', { timeout: 15000 })
    expect(await page.title()).not.toBe(RAN)

    await headlineInput(sidebar(page)).fill('Edited beside the look-alikes')
    await expect(headline(page, 'Edited beside the look-alikes')).toBeVisible({ timeout: 10000 })
    await sidebar(page).getByTestId('submit').click()
    await expect(sidebar(page).locator('.frontend-edit-status .lucide-circle-check')).toBeVisible({ timeout: 15000 })
    await page.reload()
    await expect(headline(page, 'Edited beside the look-alikes')).toBeVisible()
    expect(await page.title()).not.toBe(RAN)
  })

  test('a name in the content cannot stop the overlay as if it had already started', async ({ page }) => {
    await startEditing(page)
    await rewritePage(page, body => body.replace('<main id="content">', '<main id="content"><img name="BrandoFrontendEdit">'))
    await page.reload()
    await expect(page.getByTestId('frontend-edit-toolbar')).toBeVisible()
  })

  test('a look-alike still cannot run when the lookup itself is replaced', async ({ page }) => {
    await startEditing(page)
    const planted = await page.request.post('/e2e/setup_fixtures/frontend-edit-planted')
    expect(planted.ok()).toBeTruthy()
    await rewritePage(page, body => body.replace('<main id="content">', '<main id="content"><img name="querySelector">'))
    await page.reload()

    await expect(page.locator('brando-frontend-edit')).toHaveCount(0)
    await headline(page, 'Welcome to the page').click()
    await expect(iframe(page)).toHaveCount(0)
    expect(await page.title()).not.toBe(RAN)
  })

  // A name replaces the member the script is about to use. Without the check
  // it throws part-way or writes to the element, and the admin gets half an
  // overlay.
  for (const [name, markup] of [
    ['document addEventListener', '<img name="addEventListener">'],
    ['document body', '<img name="body">'],
    ['document cookie', '<img name="cookie">'],
    ['document createElementNS, which morphdom uses', '<img name="createElementNS">'],
    // Chromium, the browser here, keeps these under a name, so they are set
    ['window addEventListener, as a browser following the spec would', '<script>window.addEventListener = {}</script>'],
    ['window removeEventListener, as a browser following the spec would', '<script>window.removeEventListener = {}</script>']
  ]) {
    test(`the overlay does not start when a name replaces ${name}`, async ({ page }) => {
      await startEditing(page)
      await rewritePage(page, body => body.replace('<main id="content">', `<main id="content">${markup}`))
      const served = page.waitForResponse(/\/\/[^/]+\/frontend-edit$/)
      await page.reload()
      expect(await (await served).text()).toContain(markup)

      await expect(page.locator('brando-frontend-edit')).toHaveCount(0)
    })
  }

  test('a name stops the overlay outside edit mode too, leaving no button', async ({ page }) => {
    await rewritePage(page, body => body.replace('<main id="content">', '<main id="content"><img name="createRange">'))
    await page.goto('/frontend-edit')

    await expect(page.locator('img[name="createRange"]')).toHaveCount(1)
    await expect(page.locator('brando-frontend-edit')).toHaveCount(0)
  })

  test('stopping in edit mode switches edit mode off, as there is no Done button', async ({ page }) => {
    await startEditing(page)
    const editCookie = async () => (await page.context().cookies()).find(cookie => cookie.name === '_brando_frontend_edit')
    expect(await editCookie()).toBeTruthy()

    // Not `createRange` or `createElement`: on those morphdom, in the same
    // script element, throws while loading and the check never runs
    await rewritePage(page, body => body.replace('<main id="content">', '<main id="content"><img name="body">'))
    await page.reload()

    await expect(page.locator('brando-frontend-edit')).toHaveCount(0)
    expect(await editCookie()).toBeUndefined()
  })

  test("a site's own document.cookie accessor leaves the overlay working", async ({ page }) => {
    await page.goto('/frontend-edit')
    await rewritePage(page, body => body.replace('</head>', `<script>
      const real = Object.getOwnPropertyDescriptor(Document.prototype, 'cookie')
      Object.defineProperty(document, 'cookie', {
        configurable: true,
        get: () => real.get.call(document),
        set: value => real.set.call(document, value)
      })
    </script></head>`))
    await page.reload()
    expect(await page.evaluate(() => Object.hasOwn(document, 'cookie'))).toBe(true)

    await page.getByTestId('frontend-edit-toggle').click()
    await expect(page.getByTestId('frontend-edit-toolbar')).toBeVisible()
    await openBlock(page, 'Welcome to the page')
  })

  // morphdom's loader would hand itself to these and leave its global unset,
  // and edits in the sidebar would not reach the page until a reload. The
  // loaders mark the page if anything is handed to them.
  for (const [name, transform] of [
    [
      'an AMD loader',
      body => body.replace('</head>', `<script>
        window.define = function () { document.documentElement.dataset.loaderUsed = 'define' }
        window.define.amd = {}
      </script></head>`)
    ],
    [
      'CommonJS globals',
      body => body.replace('</head>', `<script>
        window.exports = {}
        window.module = { set exports(_value) { document.documentElement.dataset.loaderUsed = 'module' } }
      </script></head>`)
    ],
    ['elements named exports and module', body => body.replace('<main id="content">', '<main id="content"><img name="exports"><img name="module">')]
  ]) {
    test(`a site with ${name} still has its edits patched into the page`, async ({ page }) => {
      await startEditing(page)
      await rewritePage(page, transform)
      await page.reload()
      await expect(page.getByTestId('frontend-edit-toolbar')).toBeVisible()
      expect(await page.evaluate(() => typeof window.morphdom)).toBe('function')

      const editor = await openBlock(page, 'Welcome to the page')
      // Gone after a reload
      await page.evaluate(() => (window.__notReloaded = true))
      await headlineInput(editor).fill('Patched beside the loader')
      await expect(headline(page, 'Patched beside the loader')).toBeVisible({ timeout: 10000 })
      expect(await page.evaluate(() => window.__notReloaded)).toBe(true)
      expect(await page.evaluate(() => document.documentElement.dataset.loaderUsed)).toBeUndefined()
    })
  }

  test('a name the scripts do not use leaves the overlay working', async ({ page }) => {
    await startEditing(page)
    await rewritePage(page, body => body.replace('<main id="content">', '<main id="content"><img name="gallery">'))
    await page.reload()

    await expect(page.locator('img[name="gallery"]')).toHaveCount(1)
    await expect(page.getByTestId('frontend-edit-toolbar')).toBeVisible()
    await openBlock(page, 'Welcome to the page')
  })

  for (const [name, editorUrl] of [
    ['a script address', `javascript:parent.document.title='${RAN}';void 0//`],
    ['another origin', 'https://example.com/admin/frontend-edit'],
    ['an address without a scheme on another origin', '//example.com/admin/frontend-edit'],
    ['another admin path', '/admin/users']
  ]) {
    test(`the sidebar refuses ${name} as the editor address`, async ({ page }) => {
      await startEditing(page)
      await rewritePage(page, body => body.replace(/"editorUrl":"[^"]*"/, `"editorUrl":${JSON.stringify(editorUrl)}`))
      const served = page.waitForResponse(/\/\/[^/]+\/frontend-edit$/)
      await page.reload()
      expect(await (await served).text()).toContain(JSON.stringify(editorUrl))

      await expect(page.locator('brando-frontend-edit')).toHaveCount(0)
      await headline(page, 'Welcome to the page').click()
      await expect(iframe(page)).toHaveCount(0)
      expect(await page.title()).not.toBe(RAN)
    })
  }
})
