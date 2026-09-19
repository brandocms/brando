import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

async function project(page) {
  const client = await factory(page, 'E2eProject.Projects.Client', { name: 'Panel client', slug: 'panel-client', status: 'published', language: 'en' })
  return factory(page, 'E2eProject.Projects.Project', {
    title: 'Panel project', slug: 'panel-project', status: 'published', language: 'en', client_id: client.id,
    introduction: Array.from({ length: 25 }, () => '<p>A long introduction to check the formatting toolbar while scrolling.</p>').join(''),
  })
}

for (const context of ['field', 'block']) {
  test(`entry ${context} filtering survives selection patches and Escape clears before closing`, async ({ page }, testInfo) => {
    await page.setViewportSize({ width: 1440, height: 900 })
    if (context === 'field') {
      const entry = await project(page)
      await page.goto(`/admin/projects/projects/update/${entry.id}`)
    } else {
      await page.goto('/admin/pages/create')
      await syncLV(page)
      await page.getByRole('button', { name: 'Add block', exact: true }).click()
      await page.getByRole('button', { name: /DATASOURCE/ }).click()
      await page.getByRole('button', { name: 'Featured Projects', exact: true }).click()
    }
    await syncLV(page)
    await page.getByRole('button', { name: 'Select entries', exact: true }).click()
    const dialog = page.getByRole('dialog', { name: 'Select entries', exact: true })
    const filter = dialog.getByRole('searchbox', { name: 'Filter entries', exact: true })
    await filter.fill('Alpha')
    await expect(dialog.locator('.identifier:visible')).toHaveCount(1)
    const option = dialog.locator('.identifier:visible')
    await option.click()
    await syncLV(page)
    await expect(option).toHaveClass(/selected/)
    await expect(filter).toHaveValue('Alpha')
    await expect(dialog.locator('.identifier:visible')).toHaveCount(1)
    await filter.hover()
    await page.screenshot({ path: testInfo.outputPath(`entries-${context}-filter-hover.png`) })
    await dialog.getByRole('button', { name: 'Clear filter', exact: true }).click()
    await expect(filter).toHaveValue('')
    await expect(filter).toBeFocused()
    await filter.fill('no possible match')
    await expect(dialog.getByText('No matching entries', { exact: true })).toBeVisible()
    await filter.press('Escape')
    await expect(filter).toHaveValue('')
    await expect(dialog).toBeVisible()
    await expect(dialog.locator('.identifier.selected')).toHaveCount(1)
    await page.screenshot({ path: testInfo.outputPath(`entries-${context}-desktop.png`) })
    await page.setViewportSize({ width: 390, height: 844 })
    await page.screenshot({ path: testInfo.outputPath(`entries-${context}-mobile.png`) })
    expect(await dialog.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true)
    await filter.press('Escape')
    await expect(dialog).not.toBeVisible()
  })
}

test('selected options use equal row heights and square remove buttons', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await factory(page, 'E2eProject.Projects.Category', { title: 'Panel category', slug: 'panel-category', status: 'published', language: 'en' })
  const entry = await project(page)
  await page.goto(`/admin/projects/projects/update/${entry.id}`)
  await syncLV(page)
  await page.locator('#project_project_categories-field-base').getByRole('button', { name: 'Select', exact: true }).click()
  const dialog = page.getByRole('dialog', { name: 'Select options', exact: true })
  const option = dialog.getByRole('button', { name: 'Panel category', exact: true })
  await option.click()
  const selected = dialog.locator('.selected-label')
  const remove = selected.getByRole('button', { name: 'Remove', exact: true })
  await expect(remove).toBeVisible()
  expect((await selected.boundingBox()).height).toBeCloseTo((await option.boundingBox()).height, 0)
  const box = await remove.boundingBox()
  expect(box.width).toEqual(box.height)
  const background = await selected.evaluate(el => getComputedStyle(el).backgroundColor)
  await selected.hover()
  await expect(selected).toHaveCSS('background-color', background)
  await page.screenshot({ path: testInfo.outputPath('multiselect-desktop.png') })
  await remove.click()
  await expect(selected).toHaveCount(0)
  await option.click()
  await page.setViewportSize({ width: 390, height: 844 })
  await page.screenshot({ path: testInfo.outputPath('multiselect-mobile.png') })
  expect(await dialog.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true)
})

test('rich text toolbar follows the form toolbar at desktop and mobile widths after validation', async ({ page }, testInfo) => {
  const entry = await project(page)
  await page.goto(`/admin/projects/projects/update/${entry.id}`)
  await syncLV(page)
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 900 })
    await page.getByLabel('Title', { exact: true }).fill(`Panel project ${width}`)
    await syncLV(page)
    const menu = page.locator('[data-footnote-field="introduction"] .tiptap-menu')
    await menu.evaluate(el => window.scrollBy(0, el.getBoundingClientRect().top + 150))
    await expect.poll(async () => {
      const a = await page.locator('.form-content > .form-tabs').boundingBox()
      const b = await menu.boundingBox()
      return Math.round(b.y - a.y - a.height)
    }).toBe(8)
    await page.screenshot({ path: testInfo.outputPath(`sticky-rich-text-${width}.png`) })
  }
})

test('entry drawers retain input and use their own scrolling surface', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  for (const [trigger, suffix] of [['Meta', 'meta-drawer'], ['Revisions', 'revisions-drawer'], ['Scheduled publishing', 'scheduled-publishing-drawer']]) {
    await page.getByRole('button', { name: trigger, exact: true }).click()
    const drawer = page.locator(`[id$="-${suffix}"]`)
    await expect(drawer).toHaveCSS('background-color', 'rgb(255, 255, 255)')
    await page.waitForTimeout(350)
    if (trigger === 'Meta') await drawer.getByLabel('META title', { exact: true }).fill('Panel metadata')
    if (trigger === 'Revisions') {
      await drawer.getByRole('button', { name: 'Store current editor state', exact: true }).click()
      await expect(drawer.locator('.revisions-line').first()).toBeVisible()
    }
    await expect(drawer).toBeInViewport()
    await page.waitForTimeout(350)
    await page.screenshot({ path: testInfo.outputPath(`${suffix}-desktop.png`) })
    await page.setViewportSize({ width: 390, height: 844 })
    await page.waitForTimeout(350)
    await page.screenshot({ path: testInfo.outputPath(`${suffix}-mobile.png`) })
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    await drawer.getByRole('button', { name: 'Close', exact: true }).press('Escape')
    await expect(drawer).not.toBeVisible()
    await page.setViewportSize({ width: 1440, height: 900 })
  }
  await page.getByRole('button', { name: 'Meta', exact: true }).click()
  await expect(page.getByLabel('META title', { exact: true })).toHaveValue('Panel metadata')
})

test('listing actions align with the header rule and selection covers presence', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  expect((await page.request.post('/e2e/admin-workspace-fixtures')).ok()).toBeTruthy()
  await page.goto('/admin/projects/projects')
  await syncLV(page)
  const header = page.locator('#content-header')
  const action = header.getByRole('link', { name: 'Create new', exact: true })
  const h = await header.boundingBox(), a = await action.boundingBox(), main = await header.locator('.main').boundingBox()
  expect(a.x + a.width).toBeCloseTo(h.x + h.width, 0)
  expect(a.y + a.height).toBeCloseTo(main.y + main.height, 0)
  await page.screenshot({ path: testInfo.outputPath('listing-header-desktop.png') })
  await page.goto('/admin/pages')
  await syncLV(page)
  const entry = page.locator('.entry-link').first()
  await expect(entry).toHaveAccessibleName(await entry.innerText())
  await entry.hover()
  await expect(entry).toHaveCSS('text-decoration-line', 'none')
  await expect.poll(() => entry.evaluate(el => getComputedStyle(el, '::after').opacity)).toBe('1')
  await page.locator('.list-row').first().locator('.listing-creator').click({ modifiers: ['Shift'] })
  const bar = page.locator('.selected-rows')
  await expect(bar).toBeVisible()
  await page.waitForTimeout(350)
  const presenceCovered = await page.locator('.presences').evaluate(el => {
    const p = el.getBoundingClientRect(), bar = document.querySelector('.selected-rows'), b = bar.getBoundingClientRect()
    const x = (Math.max(p.left, b.left) + Math.min(p.right, b.right)) / 2, y = (Math.max(p.top, b.top) + Math.min(p.bottom, b.bottom)) / 2
    return bar.contains(document.elementFromPoint(x, y))
  })
  expect(presenceCovered).toBe(true)
  await page.locator('.sorts .simple-dropdown-button').press('Enter')
  await expect(page.locator('#sorts-dropdown')).toBeVisible()
  await page.waitForTimeout(350)
  await page.screenshot({ path: testInfo.outputPath('listing-panels-desktop.png') })
  await page.keyboard.press('Escape')
  await bar.getByRole('button', { name: 'Actions', exact: true }).press('Space')
  await expect(bar.locator('.dropdown-content')).toBeVisible()
  await page.setViewportSize({ width: 390, height: 844 })
  await page.waitForTimeout(350)
  await page.screenshot({ path: testInfo.outputPath('selection-bar-mobile.png') })
  await page.keyboard.press('Escape')
  await expect(bar.getByRole('button', { name: 'Actions', exact: true })).toBeFocused()
})

test('block rich text keeps its toolbar below the form controls', async ({ page }, testInfo) => {
  const text = Array.from({ length: 25 }, () => '<p>Block text with enough content to scroll through the editor.</p>').join('')
  await factory(page, 'Brando.Content.Module', {
    name: { en: 'Long text', no: 'Long text' }, namespace: { en: 'PANELS', no: 'PANELS' },
    help_text: { en: 'Toolbar spacing' }, class: 'long-text', type: 'liquid', code: '{% ref refs.body %}',
    multi: false, datasource: false, vars: [],
    refs: [{ name: 'body', description: 'Body', uid: 'panel-text-ref', data: { type: 'text', data: { text, type: 'paragraph', extensions: ['bold', 'italic', 'link', 'bullet_list'] } } }],
  })
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByRole('button', { name: 'Add block', exact: true }).click()
  await page.getByRole('button', { name: /PANELS/ }).click()
  await page.getByRole('button', { name: 'Long text', exact: true }).click()
  await syncLV(page)
  const menu = page.locator('.entry-block .tiptap-menu').first()
  const editor = page.locator('.entry-block .ProseMirror').first()
  await editor.click()
  await editor.press('Home')
  await editor.pressSequentially('Toolbar after editing. ')
  await editor.blur()
  await syncLV(page)
  await page.getByRole('button', { name: 'Advanced', exact: true }).click()
  await page.getByRole('button', { name: 'Content', exact: true }).click()
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill('Sticky toolbar')
  await page.getByLabel('URI', { exact: true }).fill('sticky-toolbar')
  await page.getByTestId('split-dropdown-button').click()
  await page.getByRole('button', { name: /Save and continue editing/ }).click()
  await expect(page).toHaveURL(/\/update\//)
  await page.reload()
  await syncLV(page)
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 900 })
    await page.waitForTimeout(350)
    await page.evaluate(() => window.scrollTo(0, 0))
    await menu.evaluate(el => window.scrollBy(0, el.getBoundingClientRect().top + 150))
    await expect.poll(async () => {
      const a = await page.locator('.form-content > .form-tabs').boundingBox(), b = await menu.boundingBox()
      return Math.round(b.y - a.y - a.height)
    }).toBe(8)
    await page.screenshot({ path: testInfo.outputPath(`sticky-block-${width}.png`) })
    const toolbar = await page.locator('.form-content > .form-tabs').boundingBox()
    await page.screenshot({ path: testInfo.outputPath(`sticky-block-detail-${width}.png`), clip: {
      x: toolbar.x, y: 0, width: toolbar.width, height: 420,
    } })
  }
})

test('Norwegian image fields use the short selection label', async ({ page }, testInfo) => {
  const entry = await project(page)
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
  await page.goto(`/admin/projects/projects/update/${entry.id}`)
  await syncLV(page)
  const field = page.locator('#project_listing_image-media')
  await expect(field.getByRole('button', { name: 'Velg bilde', exact: true })).toBeVisible()
  await field.screenshot({ path: testInfo.outputPath('image-field-norwegian.png') })
})

test('revision metadata is readable in Norwegian at desktop and mobile widths', async ({ page }, testInfo) => {
  expect((await page.request.post('/e2e/setup_fixtures/revision-panel')).ok()).toBe(true)
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  await page.getByRole('button', { name: 'Versjoner', exact: true }).click()
  const drawer = page.locator('[id$="-revisions-drawer"]')
  await expect(drawer.locator('.revision-status.is-active')).toHaveText('Aktiv')
  await expect(drawer.locator('.revision-status.is-scheduled')).toHaveText('Planlagt')
  await expect(drawer.locator('.revision-protection')).toHaveText('Beskyttet')
  await expect(drawer.getByText('Inaktiv', { exact: true })).toHaveCount(3)
  await expect(drawer).toContainText('Anne-Kristine Søndergaard')
  const author = drawer.locator('.revisions-line.active .modal-person')
  await expect(author).toHaveText('Anne-Kristine Søndergaard')
  await expect.poll(() => author.locator('img').evaluate(img => img.complete && img.naturalWidth > 0)).toBe(true)
  await expect(drawer.locator('.modal-person-avatar > span')).toHaveText('N')
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 1000 })
    await page.waitForTimeout(350)
    expect(await drawer.locator('.drawer-form').evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true)
    await drawer.screenshot({ path: testInfo.outputPath(`revisions-readable-${width}.png`) })
    if (width === 1440) await drawer.locator('.revisions-table').screenshot({ path: testInfo.outputPath('revisions-table-desktop.png') })
    const row = drawer.locator('.revisions-line.active')
    await row.scrollIntoViewIfNeeded()
    if (width === 390) await row.screenshot({ path: testInfo.outputPath('revision-card-mobile.png') })
    await row.getByTestId('circle-dropdown-button').click()
    await expect(row.getByRole('button', { name: 'Beskytt versjon', exact: true })).toBeVisible()
    await page.keyboard.press('Escape')
    await expect(drawer).toBeVisible()
  }
})
