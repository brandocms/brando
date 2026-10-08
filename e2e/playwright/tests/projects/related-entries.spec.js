import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

test('related entries can be cleared, saved and selected again without losing other fields', async ({ page }, testInfo) => {
  const client = await factory(page, 'E2eProject.Projects.Client', { name: 'Havglimt', slug: 'havglimt', status: 'published', language: 'en' })
  // Exercise a real identifier cover and a coverless entry in the same list.
  await page.route('**/media/images/identifier-cover.jpg', route => route.fulfill({ path: 'fixtures/image.jpg', contentType: 'image/jpeg' }))
  const cover = await factory(page, 'Brando.Images.Image', {
    path: 'images/identifier-cover.jpg', sizes: { thumb: 'images/identifier-cover.jpg' }, width: 292, height: 173, status: 'processed',
  })
  await factory(page, 'E2eProject.Projects.Project', {
    title: 'The garden rooms', slug: 'the-garden-rooms', client_id: client.id, status: 'published', language: 'en', listing_image_id: cover.id,
    introduction: '<p>Rooms overlooking the garden.</p>',
  })
  const introduction = '<h2>A slower pace by the sea</h2><p>Light-filled rooms, quiet gardens and the open water.</p><p>A place to arrive, settle in and stay a little longer.</p>'
  const entry = await factory(page, 'E2eProject.Projects.Project', {
    title: 'Havglimt retreat', slug: 'havglimt-retreat', client_id: client.id, status: 'published', language: 'en', introduction,
  })
  const url = `/admin/projects/projects/update/${entry.id}`
  await page.setViewportSize({ width: 1440, height: 1100 })
  await page.goto(url)
  await syncLV(page)
  const field = page.locator('.entries-input')
  const selected = field.locator('.selected-entries .identifier')
  const input = page.locator('[data-footnote-field="introduction"] .tiptap-text')
  const dialog = page.getByRole('dialog', { name: 'Select entries', exact: true })
  const filter = dialog.getByRole('searchbox', { name: 'Filter entries', exact: true })

  async function select(title) {
    await field.getByRole('button', { name: 'Select entries', exact: true }).click()
    await filter.fill(title)
    // The filter hides the other entries a moment after typing: wait for it
    const match = dialog.locator('.identifier:visible')
    await expect(match).toHaveCount(1)
    await match.click()
    await syncLV(page)
    await filter.press('Escape')
    await filter.press('Escape')
    await expect(dialog).not.toBeVisible()
  }

  async function saveAndReopen() {
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/projects\/projects$/)
    await page.goto(url)
    await syncLV(page)
  }

  await expect(page.locator('.gallery-input .media-field-meta')).toHaveText('Images up to 10.2 MB · Videos up to 100 MB each')
  await expect(field.getByRole('button', { name: 'Clear all', exact: true })).toBeDisabled()
  await field.screenshot({ path: testInfo.outputPath('related-entries-empty.png') })
  await select('The garden rooms')
  await select('Beta')
  await field.getByRole('button', { name: 'Select entries', exact: true }).click()
  const coveredOption = dialog.locator('.identifier').filter({ hasText: 'The garden rooms' })
  await expect(coveredOption.locator('.identifier-cover img')).toBeVisible()
  await expect(coveredOption).toHaveAttribute('aria-pressed', 'true')
  await dialog.screenshot({ path: testInfo.outputPath('joined-identifiers-picker.png') })
  await filter.press('Escape')
  await saveAndReopen()
  await expect(selected).toHaveCount(2)
  const thumbnail = selected.first().locator('.identifier-cover img')
  await expect(thumbnail).toBeVisible()
  await expect.poll(() => thumbnail.evaluate(img => img.complete && img.naturalWidth > 0)).toBe(true)
  await expect(selected.nth(1).locator('.identifier-cover [data-icon]')).toBeVisible()
  await expect(input).toHaveValue(introduction)

  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 1100 })
    await field.evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }))
    await page.mouse.move(0, 0)
    expect(await field.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true)
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true)
    await field.screenshot({ path: testInfo.outputPath(`related-entries-selected-${width}.png`) })
    if (width === 1440) {
      await selected.first().getByRole('button', { name: 'Remove', exact: true }).hover()
      await field.screenshot({ path: testInfo.outputPath('related-entries-remove-hover.png') })
      await page.mouse.move(0, 0)
      await page.locator('[data-footnote-field="introduction"]').evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }))
    }
    await page.screenshot({ path: testInfo.outputPath(`project-media-fields-${width}.png`) })
  }

  await field.getByRole('button', { name: 'Clear all', exact: true }).press('Enter')
  await expect(selected).toHaveCount(0)
  await expect(field.getByText('No selected entries', { exact: true })).toBeVisible()
  await page.getByLabel('Title', { exact: true }).fill('Havglimt retreat, updated')
  await syncLV(page)
  await saveAndReopen()
  await expect(selected).toHaveCount(0)
  await expect(input).toHaveValue(introduction)
  await expect(page.getByLabel('Title', { exact: true })).toHaveValue('Havglimt retreat, updated')
  await select('The garden rooms')
  await select('Beta')
  await saveAndReopen()
  await expect(selected).toHaveCount(2)
  await expect(selected.first()).toContainText('The garden rooms')
  await expect(input).toHaveValue(introduction)

  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
  await page.reload()
  await syncLV(page)
  await expect(field.getByRole('button', { name: 'Velg innlegg', exact: true })).toBeVisible()
  await expect(field.getByRole('button', { name: 'Fjern alle', exact: true })).toBeEnabled()
  const gallery = page.locator('.gallery-input .media-gallery--empty')
  await expect(gallery.getByRole('button', { name: 'Last opp medier', exact: true })).toBeVisible()
  await expect(gallery.locator('.media-field-meta')).toHaveText('Bilder opptil 10.2 MB · Videoer opptil 100 MB per fil')
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 1100 })
    await field.evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }))
    expect(await field.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true)
    expect(await gallery.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true)
    await field.screenshot({ path: testInfo.outputPath(`related-entries-norwegian-${width}.png`) })
    await gallery.screenshot({ path: testInfo.outputPath(`project-gallery-norwegian-${width}.png`) })
  }
})
