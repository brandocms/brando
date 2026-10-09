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
// tooltip whose button LiveView takes away or moves goes with it.
test('tooltips follow LiveView patches', async ({ page }) => {
  await openProject(page)

  const field = page.locator('#project_cover_file-media')
  const library = field.locator('.media-field-split > .media-button--icon').first()

  await library.hover()
  await expect(tooltip(page)).toBeVisible()

  // Filling the field patches its buttons while the pointer rests there
  // (Configure comes in before the library). Wherever the tooltip still
  // shows, it sits just above the button it names.
  await field.locator('input[type="file"]').setInputFiles('./fixtures/test.pdf')
  await expect(field).not.toHaveClass(/media-field--empty/, { timeout: 30000 })
  await expect.poll(() => page.evaluate(() => {
    const tip = document.getElementById('brando-tooltip')
    if (!tip.classList.contains('is-visible')) return 'hidden'
    const named = [...document.querySelectorAll('[data-tooltip]')].find(el => el.dataset.tooltip === tip.textContent)
    if (!named) return `stale: ${tip.textContent}`
    const t = tip.getBoundingClientRect()
    const b = named.getBoundingClientRect()
    const above = t.bottom <= b.top + 1 && b.top - t.bottom < 12
    const overlaps = t.left < b.right && t.right > b.left
    return above && overlaps ? 'beside its button' : 'misplaced'
  })).toMatch(/^(hidden|beside its button)$/)

  const replace = field.locator('.media-field-split > .upload-trigger.media-button--icon')
  await expect(replace).toBeVisible()
  await replace.hover()
  await expect(tooltip(page)).toBeVisible()
  await expect(tooltip(page)).toHaveText(await replace.getAttribute('data-tooltip'))
})

// A drag (Sortable uses its pointer fallback everywhere) crosses drag
// handles and buttons with a button held down: none of them shows its
// tooltip, not even straight after another one closed.
test('no tooltips while a button is held down', async ({ page }) => {
  await openProject(page)

  const upload = page.locator('#project_listing_image-media .media-field-split > .upload-trigger')
  const [first, second] = [
    page.locator('#project_cover_video-media .media-field-split > .media-button--icon').first(),
    page.locator('#project_cover_video-media .media-field-split > .media-button--icon').nth(1),
  ]
  const centre = async locator => {
    const box = await locator.boundingBox()
    return [box.x + box.width / 2, box.y + box.height / 2]
  }

  const neutral = page.locator('#project_cover_video-media .media-field-name')

  // A tooltip just closed by leaving its button would let the next one show
  // at once; pressing and dragging must not use that.
  await first.hover()
  await expect(tooltip(page)).toBeVisible()
  await page.mouse.move(...await centre(neutral))
  await page.mouse.down()
  await expect(tooltip(page)).toBeHidden()
  await page.mouse.move(...await centre(second), { steps: 3 })
  await page.mouse.move(...await centre(upload), { steps: 4 })
  await page.mouse.move(...await centre(first), { steps: 4 })
  await page.waitForTimeout(700)
  await expect(tooltip(page)).toBeHidden()
  await page.mouse.move(...await centre(neutral))
  await page.mouse.up()
})

// Moving over a button's icon and label is one hover: the delay runs once.
test('the hover delay runs from entering the button, not from each child', async ({ page }) => {
  await openProject(page)

  const library = page.locator('#project_cover_video-media .media-field-split > .media-button--icon').first()
  const box = await library.boundingBox()
  await page.evaluate(() => {
    window.__tooltipShownAt = null
    const tip = () => document.getElementById('brando-tooltip')
    new MutationObserver(() => {
      if (!window.__tooltipShownAt && tip()?.classList.contains('is-visible')) window.__tooltipShownAt = performance.now()
    }).observe(document.body, { subtree: true, attributes: true, attributeFilter: ['class'] })
  })

  // Enter on the button's edge, then cross its icon and back to its edge
  await page.mouse.move(box.x + 2, box.y + 2)
  const enteredAt = await page.evaluate(() => performance.now())
  for (const [x, y] of [[box.x + box.width / 2, box.y + box.height / 2], [box.x + box.width - 3, box.y + 3], [box.x + box.width / 2, box.y + box.height / 2]]) {
    await page.waitForTimeout(120)
    await page.mouse.move(x, y)
  }
  await expect(tooltip(page)).toBeVisible()
  const shownAt = await page.evaluate(() => window.__tooltipShownAt)
  // A restarted delay would show it 400 ms after the last move, at 760 ms
  expect(shownAt - enteredAt).toBeLessThan(650)
})

// Tab to a button below the fold: the browser scrolls it into view, and the
// tooltip stays with it instead of closing on that scroll.
test('keyboard focus that scrolls its button into view keeps the tooltip', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 420 })
  await openProject(page)
  await page.evaluate(() => window.scrollTo(0, 0))

  const gallery = page.locator('.gallery-input .gallery-actions .segmented-buttons')
  const upload = gallery.locator('> .upload-trigger')
  const images = gallery.locator('> .media-button--icon').first()
  await expect(images).not.toBeInViewport()

  await upload.evaluate(el => el.focus({ preventScroll: true }))
  await page.keyboard.press('Tab')
  await expect(images).toBeFocused()
  await expect(images).toBeInViewport()
  await expect(tooltip(page)).toBeVisible()
  await expect(tooltip(page)).toHaveText(await images.getAttribute('data-tooltip'))
  const tip = await tooltip(page).boundingBox()
  const button = await images.boundingBox()
  expect(Math.abs(tip.y + tip.height - button.y)).toBeLessThan(12)
})

// A tooltip the accessible name already says is not announced twice; one
// that adds to it describes the element while it shows.
test('the tooltip describes an element only with words its name lacks', async ({ page }) => {
  await openProject(page)
  await page.evaluate(() => {
    const host = document.createElement('div')
    host.id = 'tooltip-names'
    host.innerHTML = `
      <button type="button" id="named-start">Start</button>
      <button type="button" id="named-status" aria-label="Status: Draft" data-tooltip="draft">•</button>
      <button type="button" id="named-shortcut" aria-label="Bold" data-tooltip="Bold · Ctrl B">B</button>`
    document.body.prepend(host)
  })

  await page.locator('#named-start').focus()
  await page.keyboard.press('Tab')
  await expect(tooltip(page)).toBeVisible()
  await expect(page.locator('#named-status')).not.toHaveAttribute('aria-describedby')

  await page.keyboard.press('Tab')
  await expect(tooltip(page)).toHaveText('Bold · Ctrl B')
  await expect(page.locator('#named-shortcut')).toHaveAttribute('aria-describedby', 'brando-tooltip')
  await page.keyboard.press('Escape')
  await expect(page.locator('#named-shortcut')).not.toHaveAttribute('aria-describedby')
})
