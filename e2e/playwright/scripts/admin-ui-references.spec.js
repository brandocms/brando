// Reference screenshots that no E2E spec takes. Run through
// scripts/admin-ui-references.mjs, never in the E2E suite: the files sit outside
// tests/ and only the references config matches them. Each test runs in its own
// SQL sandbox, so the data it creates is rolled back afterwards.
import { test, expect } from '../test-support/setupAuth'
import { syncLV, confirmUploadFolder } from '../utils'

const sommerro = 'Put image1 on the Index page and create a case called Sommerro with image2'

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

// Seeded pages are inserted without identifiers; the assistant's search reads them.
async function syncIdentifiers(page) {
  await page.goto('/admin/config/utils')
  await syncLV(page)
  await page.getByRole('button', { name: 'Sync identifiers' }).click()
  await syncLV(page)
}

async function proposeSommerro(page) {
  await page.goto('/admin/assistant')
  await syncLV(page)
  await page.locator('#assistant-upload input.file-input').setInputFiles(['./fixtures/image.jpg', './fixtures/image2.jpg'])
  await expect(page.locator('.assistant-attachment:not(.is-pending)')).toHaveCount(2, { timeout: 30000 })
  // The upload drawer clears itself four seconds after the last file.
  await page.waitForTimeout(4500)
  await page.getByLabel('Message').fill(sommerro)
  await page.getByLabel('Message').press('Enter')
  await expect(page.locator('.assistant-proposal')).toBeVisible({ timeout: 30000 })
  await page.waitForTimeout(1500)
}

test('assistant: empty workspace', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/assistant')
  await syncLV(page)
  await expect(page.getByRole('heading', { name: 'No proposal yet' })).toBeVisible()
  await page.waitForTimeout(500)
  await page.screenshot({ path: testInfo.outputPath('assistant-empty-desktop.png') })
})

test('assistant: Sommerro proposal from review to applied', async ({ page }, testInfo) => {
  test.setTimeout(120000)
  await page.setViewportSize({ width: 1440, height: 1000 })
  await syncIdentifiers(page)
  await proposeSommerro(page)
  await expect(page.getByRole('heading', { name: 'Ready for your review' })).toBeVisible()
  await page.screenshot({ path: testInfo.outputPath('assistant-review-desktop.png') })

  await page.locator('.assistant-card').first().getByRole('button', { name: 'Preview page' }).click()
  const frame = page.frameLocator('.assistant-frame iframe')
  await expect(frame.locator('.brando-proposal-highlight').first()).toBeAttached({ timeout: 15000 })
  await page.waitForTimeout(1500)
  await page.screenshot({ path: testInfo.outputPath('assistant-preview-desktop.png') })
  await page.getByRole('button', { name: 'All changes' }).click()
  await page.waitForTimeout(600)

  await page.getByTitle('Attach images from the media library', { exact: true }).click()
  await expect(page.locator('#image-picker')).toBeVisible()
  await page.waitForTimeout(1000)
  await page.screenshot({ path: testInfo.outputPath('assistant-library-desktop.png') })
  await page.keyboard.press('Escape')
  await expect(page.locator('#image-picker')).toBeHidden()

  await page.getByRole('button', { name: /^Apply / }).click()
  await expect(page.getByRole('heading', { name: 'Applied' })).toBeVisible({ timeout: 20000 })
  await page.waitForTimeout(600)
  await page.screenshot({ path: testInfo.outputPath('assistant-applied-desktop.png') })

  await page.setViewportSize({ width: 390, height: 844 })
  await page.waitForTimeout(700)
  await page.screenshot({ path: testInfo.outputPath('assistant-applied-mobile.png'), fullPage: true })
})

test('assistant: proposal that needs changes', async ({ page }, testInfo) => {
  test.setTimeout(120000)
  await page.setViewportSize({ width: 1440, height: 1000 })
  // An existing case already uses the slug the proposal wants.
  const client = await factory(page, 'E2eProject.Projects.Client', { name: 'Sommerro', slug: 'sommerro-client', status: 'published', language: 'en' })
  await factory(page, 'E2eProject.Projects.Project', {
    title: 'Sommerro', slug: 'sommerro', introduction: '<p>The existing Sommerro case.</p>', client_id: client.id, status: 'published', language: 'en',
  })
  await syncIdentifiers(page)
  await proposeSommerro(page)
  await expect(page.getByRole('heading', { name: 'Needs changes' })).toBeVisible()
  await page.screenshot({ path: testInfo.outputPath('assistant-needs-changes-desktop.png') })
})

// The related-entries spec takes these too, but clicks its filter result before
// the client-side filter has hidden the others; wait for it here.
test('related entries: picker and selected field', async ({ page }, testInfo) => {
  const client = await factory(page, 'E2eProject.Projects.Client', { name: 'Havglimt', slug: 'havglimt', status: 'published', language: 'en' })
  await page.route('**/media/images/identifier-cover.jpg', route => route.fulfill({ path: 'fixtures/image.jpg', contentType: 'image/jpeg' }))
  const cover = await factory(page, 'Brando.Images.Image', {
    path: 'images/identifier-cover.jpg', sizes: { thumb: 'images/identifier-cover.jpg' }, width: 292, height: 173, status: 'processed',
  })
  await factory(page, 'E2eProject.Projects.Project', {
    title: 'The garden rooms', slug: 'the-garden-rooms', client_id: client.id, status: 'published', language: 'en', listing_image_id: cover.id,
    introduction: '<p>Rooms overlooking the garden.</p>',
  })
  const entry = await factory(page, 'E2eProject.Projects.Project', {
    title: 'Havglimt retreat', slug: 'havglimt-retreat', client_id: client.id, status: 'published', language: 'en',
    introduction: '<h2>A slower pace by the sea</h2><p>Light-filled rooms, quiet gardens and the open water.</p><p>A place to arrive, settle in and stay a little longer.</p>',
  })
  const url = `/admin/projects/projects/update/${entry.id}`
  await page.setViewportSize({ width: 1440, height: 1100 })
  await page.goto(url)
  await syncLV(page)
  const field = page.locator('.entries-input')
  const dialog = page.getByRole('dialog', { name: 'Select entries', exact: true })
  const filter = dialog.getByRole('searchbox', { name: 'Filter entries', exact: true })

  for (const title of ['The garden rooms', 'Beta']) {
    await field.getByRole('button', { name: 'Select entries', exact: true }).click()
    await filter.fill(title)
    await expect(dialog.locator('.identifier:visible')).toHaveCount(1)
    await dialog.locator('.identifier:visible').click()
    await syncLV(page)
    await filter.press('Escape')
    await filter.press('Escape')
    await expect(dialog).not.toBeVisible()
  }

  await field.getByRole('button', { name: 'Select entries', exact: true }).click()
  await expect(dialog.locator('.identifier').filter({ hasText: 'The garden rooms' }).locator('.identifier-cover img')).toBeVisible()
  await page.waitForTimeout(500)
  await page.screenshot({ path: testInfo.outputPath('joined-identifiers-picker.png') })
  await filter.press('Escape')
  await expect(dialog).not.toBeVisible()

  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/projects\/projects$/)
  await page.goto(url)
  await syncLV(page)
  const thumbnail = field.locator('.selected-entries .identifier .identifier-cover img').first()
  await expect.poll(() => thumbnail.evaluate(img => img.complete && img.naturalWidth > 0)).toBe(true)
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 1100 })
    await page.waitForTimeout(600)
    await field.evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }))
    await page.mouse.move(0, 0)
    await field.screenshot({ path: testInfo.outputPath(`related-entries-selected-${width}.png`) })
  }
})

// The block-media-fields spec takes these as element screenshots, which since
// the entry header moved now catch the sticky toolbar over the field. Here the
// field is centred below the toolbar and clipped from the page.
test('image refs while processing', async ({ page }, testInfo) => {
  test.setTimeout(90000)
  const picture = page.locator('.picture-block .media-field--block:visible')
  let capture = null
  // Inline Oban finishes the image at once: hold the socket frames after the
  // unprocessed render arrives, take the shot, then let the rest through.
  await page.routeWebSocket('**/live/websocket*', socket => {
    const server = socket.connectToServer()
    let messages = Promise.resolve()
    server.onMessage(message => {
      messages = messages.then(async () => {
        if (page.isClosed()) return
        socket.send(message)
        if (!capture) return
        await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))))
        if (await picture.getAttribute('data-processing-image').catch(() => null) !== 'true') return
        const pending = capture
        capture = null
        try { await pending.run(); pending.resolve() } catch (error) { pending.reject(error) }
      })
    })
  })
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill('Image processing proportions')
  await page.getByLabel('URI').fill('image-processing-proportions')
  for (const module of ['Single Image with Caption', 'Styled Header']) {
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await page.getByRole('button', { name: module, exact: true }).click()
    await syncLV(page)
  }
  const portrait = await page.evaluate(() => {
    const canvas = document.createElement('canvas')
    canvas.width = 240; canvas.height = 400
    const context = canvas.getContext('2d')
    context.fillStyle = '#dce7d3'; context.fillRect(0, 0, 240, 400)
    context.fillStyle = '#254e3f'; context.fillRect(16, 16, 208, 368)
    return canvas.toDataURL('image/png').split(',')[1]
  })
  for (const [shape, file] of [
    ['portrait', { name: 'portrait.png', mimeType: 'image/png', buffer: Buffer.from(portrait, 'base64') }],
    ['landscape', './fixtures/image.jpg'],
  ]) {
    const captured = new Promise((resolve, reject) => {
      capture = { resolve, reject, run: async () => {
        await expect(picture.locator('.media-field-meta')).toHaveText(/\d+ × \d+/)
        await picture.evaluate(el => window.liveSocket.main.getHook(el).showProgress({ status: 'processing' }))
        await expect(picture.getByRole('status')).toHaveText('Processing image…')
        // Something re-scrolls the page once after an upload; settle first.
        await page.waitForTimeout(1000)
        await picture.evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }))
        await page.waitForTimeout(300)
        const box = await picture.boundingBox()
        await page.screenshot({ path: testInfo.outputPath(`image-ref-processing-${shape}.png`), clip: box })
        await picture.evaluate(el => window.liveSocket.main.getHook(el).showProgress(null))
      } }
    })
    await picture.locator('input[type="file"]').setInputFiles(file)
    await confirmUploadFolder(page)
    await captured
    await expect(picture.locator('.media-field-preview img')).toBeVisible({ timeout: 20000 })
  }
})

// The AI looks side by side (docs/admin-ui-design.md, "AI actions and
// suggestions"). AI controls only render when a provider is configured, which
// an E2E run is not, so the sheet is the components' own markup, copied from
// the rendered screens and drawn by the admin's stylesheets on an admin page.
test('ai actions and suggestions: composed sheet', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin')
  await syncLV(page)
  const sparkles = '<span data-icon="" class="lucide-sparkles" aria-hidden="true"></span>'
  const action = (label, extra = '') => `<button type="button" class="ai-action ${extra}">${sparkles}${label}</button>`
  await page.evaluate(({ sparkles, buildWithAI, describe, rewrite, review }) => {
    const style = document.createElement('style')
    style.textContent = `
      #ai-reference-sheet { position: absolute; top: 0; left: 0; z-index: 100000; isolation: isolate; box-sizing: border-box; width: 1000px; padding: 28px; background: var(--brando-surface); }
      #ai-reference-sheet .ai-sheet-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 28px; align-items: start; }
      #ai-reference-sheet .ai-sheet-column { display: grid; gap: 24px; justify-items: start; }
      #ai-reference-sheet .ai-sheet-column > * { width: 100%; }
      #ai-reference-sheet .ai-sheet-actions { display: flex; gap: 12px; width: auto; }
      body > :not(#ai-reference-sheet) { visibility: hidden; }
      #ai-reference-sheet .seo-audit-details-grid { display: block; }
      #ai-reference-sheet .admin-workspace, #ai-reference-sheet .seo-audit { margin: 0; padding: 0; min-height: 0; }
      #ai-reference-sheet .tiptap-ai-proposal { margin-block: 28px 0; }`
    document.head.append(style)
    const sheet = document.createElement('div')
    sheet.id = 'ai-reference-sheet'
    sheet.innerHTML = `
      <div class="ai-sheet-grid">
        <div class="ai-sheet-column">
          <div class="ai-sheet-actions">${buildWithAI}${describe}</div>
          <div class="brando-form"><div class="form-content"><div class="drawer-form"><div class="brando-input">
            <div class="field-wrapper"><div class="label-wrapper"><label class="control-label"><span>Meta title</span></label></div>
              <div class="field-base"><div class="input-with-action has-action">
                <input type="text" class="text has-ai-action" aria-label="Meta title">
                <button type="button" class="ai-action is-icon ai-generate-button" aria-label="Generate with AI">${sparkles}</button>
              </div></div>
            </div>
          </div></div></div></div>
          <div class="brando-form"><div class="form-content"><div class="drawer-form">
            <div class="field-wrapper"><div class="label-wrapper"><label class="control-label"><span>Alternative text</span></label></div>
              <div class="field-base"><div class="i18n-field i18n-text">
                <div class="i18n-head">
                  <div class="i18n-tabs" role="tablist" aria-label="Alternative text">
                    <button type="button" role="tab" class="i18n-tab is-active" aria-selected="true">en</button><button type="button" role="tab" class="i18n-tab" aria-selected="false">no</button>
                  </div>
                  <button type="button" class="ai-action is-compact i18n-suggest">${sparkles}Suggest alt text</button>
                </div>
                <div role="tabpanel" class="i18n-panel is-active"><input type="text" class="text" aria-label="Alternative text (English)"></div>
              </div></div>
            </div>
          </div></div></div>
        </div>
        <div class="admin-workspace settings-workspace seo-workspace"><section class="workspace-panel seo-audit"><div class="seo-audit-details-grid">
          <div class="seo-search-preview">
            <span class="seo-preview-url">/</span>
            <div class="seo-preview-title">Index</div>
            <p>Welcome to Brando, the content system for considered websites.</p>
            <div class="seo-preview-actions"><a href="#" class="seo-row-action">Open entry</a>${rewrite}${review}</div>
            <div class="seo-critique ai-proposal" role="status">
              <h4 class="ai-proposal-label">${sparkles}AI review</h4>
              <ul><li>The description repeats the title.</li><li>Mention the location early.</li><li>Keep it under 155 characters.</li></ul>
            </div>
          </div>
        </div></section></div>
      </div>
      <div class="tiptap-ai-proposal ai-proposal" role="region" aria-label="AI suggestion">
        <span class="tiptap-ai-heading ai-proposal-label">${sparkles}AI suggestion</span>
        <span class="tiptap-ai-text">Our rooms face the sea, with wide windows and quiet mornings on the terrace.</span>
        <span class="tiptap-ai-actions ai-proposal-actions">
          <button type="button" class="primary">Accept</button><button type="button">Discard</button><button type="button" class="is-ai">${sparkles}Try again</button>
        </span>
      </div>`
    document.body.append(sheet)
  }, {
    sparkles,
    buildWithAI: action('Build with AI'),
    describe: action('Describe 3 images', 'is-primary'),
    rewrite: action('Rewrite description'),
    review: action('Review with AI'),
  })
  const sheet = page.locator('#ai-reference-sheet')
  await expect(sheet.locator('.ai-action')).toHaveCount(6)
  await page.waitForTimeout(300)
  await sheet.screenshot({ path: testInfo.outputPath('ai-actions-and-suggestions.png'), animations: 'disabled' })
})
