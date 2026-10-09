import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// One button pattern for the media fields (#3093): Upload keeps its label,
// every other source is its icon alone, named by a visually hidden label and
// shown in the shared tooltip (`data-tooltip`, assets/src/tooltips.js).
// Driven in Norwegian; the checks compare the tooltip with the button's own
// label instead of naming the copy.

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

async function openProject(page) {
  const client = await factory(page, 'E2eProject.Projects.Client', { name: 'Media client', slug: 'media-client', status: 'published', language: 'en' })
  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: 'Media buttons', slug: 'media-buttons', client_id: client.id, status: 'published', language: 'en', introduction: '<p>Intro</p>',
  })
  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)
}

// The first button group of the listing image, cover video, cover file and
// gallery fields
const groups = page => [
  page.locator('#project_listing_image-media .media-field-split').first(),
  page.locator('#project_cover_video-media .media-field-split').first(),
  page.locator('#project_cover_file-media .media-field-split').first(),
  page.locator('.gallery-input .gallery-actions .segmented-buttons'),
]

const tooltip = page => page.getByRole('tooltip')

test.beforeEach(async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
  await page.setViewportSize({ width: 1440, height: 1000 })
})

test('empty media fields share one row: Upload labelled, the other sources as icons', async ({ page }) => {
  await openProject(page)

  const layout = group => group.evaluate(el => [...el.querySelectorAll(':scope > button')].map(button => {
    const hidden = button.querySelector('.media-button-label')
    return {
      iconOnly: button.classList.contains('media-button--icon'),
      tooltip: button.dataset.tooltip ?? null,
      hiddenLabel: hidden?.textContent.trim() ?? null,
      labelShown: hidden ? hidden.getBoundingClientRect().width > 2 : button.textContent.trim() !== '',
      title: button.getAttribute('title'),
      top: Math.round(button.getBoundingClientRect().top),
    }
  }))

  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 1000 })

    for (const group of groups(page)) {
      await group.scrollIntoViewIfNeeded()
      const [upload, ...sources] = await layout(group)
      expect(sources.length).toBeGreaterThan(0)

      expect(upload).toMatchObject({ iconOnly: false, tooltip: null, labelShown: true, title: null })
      await expect(group.locator(':scope > button').first()).toHaveClass(/upload-trigger/)

      for (const source of sources) {
        expect(source).toMatchObject({ iconOnly: true, labelShown: false, title: null })
        expect(source.tooltip).toBe(source.hiddenLabel)
        expect(source.top).toBe(upload.top)
      }

      // The hidden label stays the accessible name
      for (const [index, source] of sources.entries()) {
        await expect(group.locator(':scope > button').nth(index + 1)).toHaveAccessibleName(source.hiddenLabel)
      }
    }
  }
})

test('the tooltip shows on hover and keyboard focus, and goes on leave and Escape', async ({ page }) => {
  await openProject(page)

  const field = page.locator('#project_listing_image-media')
  const upload = field.locator('.media-field-split > .upload-trigger')
  const library = field.locator('.media-field-split > .media-button--icon').first()
  const text = await library.getAttribute('data-tooltip')

  await library.hover()
  await expect(tooltip(page)).toBeVisible()
  await expect(tooltip(page)).toHaveText(text)
  // Above the button, clear of it
  const tip = await tooltip(page).boundingBox()
  const button = await library.boundingBox()
  expect(tip.y + tip.height).toBeLessThanOrEqual(button.y)
  // Repeating the name, the tooltip doesn't describe the button too
  await expect(library).not.toHaveAttribute('aria-describedby')

  await page.mouse.move(5, 995)
  await expect(tooltip(page)).toBeHidden()

  await upload.focus()
  await page.keyboard.press('Tab')
  await expect(library).toBeFocused()
  await expect(tooltip(page)).toBeVisible()
  await expect(tooltip(page)).toHaveText(text)

  await page.keyboard.press('Escape')
  await expect(tooltip(page)).toBeHidden()
  await expect(library).toBeFocused()

  await page.keyboard.press('Shift+Tab')
  await expect(upload).toBeFocused()
  await expect(tooltip(page)).toBeHidden()
  await page.keyboard.press('Tab')
  await expect(tooltip(page)).toHaveText(text)
  await library.blur()
  await expect(tooltip(page)).toBeHidden()
})

// A button LiveView adds after the page loaded gets its tooltip too, and a
// tooltip whose button LiveView takes away goes with it.
test('tooltips follow LiveView patches', async ({ page }) => {
  await openProject(page)

  const field = page.locator('#project_cover_file-media')
  const library = field.locator('.media-field-split > .media-button--icon').first()

  await library.hover()
  await expect(tooltip(page)).toBeVisible()
  const box = await library.boundingBox()
  const pointer = { x: box.x + box.width / 2, y: box.y + box.height / 2 }

  // Filling the field replaces its buttons while the pointer rests there.
  // The tooltip goes with the library's button: hidden, or the one now under
  // the pointer, never a label for a button that has moved.
  await field.locator('input[type="file"]').setInputFiles('./fixtures/test.pdf')
  await expect(field).not.toHaveClass(/media-field--empty/, { timeout: 30000 })
  await expect.poll(() => page.evaluate(({ x, y }) => {
    const tip = document.getElementById('brando-tooltip')
    if (!tip.matches(':popover-open')) return 'hidden'
    const under = document.elementFromPoint(x, y)?.closest('[data-tooltip]')
    return under?.dataset.tooltip === tip.textContent ? 'follows the pointer' : `stale: ${tip.textContent}`
  }, pointer)).toMatch(/^(hidden|follows the pointer)$/)

  const replace = field.locator('.media-field-split > .upload-trigger.media-button--icon')
  await expect(replace).toBeVisible()
  await replace.hover()
  await expect(tooltip(page)).toBeVisible()
  await expect(tooltip(page)).toHaveText(await replace.getAttribute('data-tooltip'))
})
