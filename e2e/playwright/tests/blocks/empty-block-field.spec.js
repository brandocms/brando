import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// An empty block field offers the modules this field usually starts with
// (Brando.Content.StartingModules). The seeds hold six Norwegian cases: three
// start with Heading, two with a Wide section holding Single Image with
// Caption, one with Rich Text Article; Example module is used but never
// first. Articles pin Rich Text Article with `starts_with:` and have no
// content to count.

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

const emptyCase = async page => {
  const slug = `tom-case-${Date.now()}-${Math.floor(Math.random() * 1000)}`
  return factory(page, 'E2eProject.Projects.Project', { title: 'Tom case', slug, status: 'draft', language: 'no' })
}

const noOverflow = page =>
  page.evaluate(() => document.documentElement.scrollWidth - document.documentElement.clientWidth)

// The tiles' rows (how many on each), and the words of their names that a
// line break splits. Names are swapped for long, grouped ones first, as sites
// name their modules ("Tekst | Oppsummeringsliste").
const tileLayout = tiles =>
  tiles.evaluateAll(elements => {
    const names = ['Overskrift | Tekst', 'Case/Artikkel media', 'Tekst | Oppsummeringsliste', 'Innholdsfortegnelse | Kapitteloversikt']
    const rows = {}
    const split = []

    elements.forEach((tile, index) => {
      const name = tile.querySelector('.blocks-welcome-module-name')
      name.textContent = names[index % names.length].replace(' | ', '\u00A0| ')
      const top = Math.round(tile.getBoundingClientRect().top)
      rows[top] = (rows[top] || 0) + 1

      const text = name.firstChild
      for (const word of text.textContent.matchAll(/[^\s\u00A0]+/g)) {
        const range = document.createRange()
        range.setStart(text, word.index)
        range.setEnd(text, word.index + word[0].length)
        const lines = new Set([...range.getClientRects()].map(rect => Math.round(rect.top)))
        if (lines.size > 1) split.push(word[0])
      }

      const hint = tile.querySelector('.blocks-welcome-module-count')
      if (hint && hint.getBoundingClientRect().height > parseFloat(getComputedStyle(hint).lineHeight) * 1.5) split.push(hint.textContent.trim())
    })

    return { rows: Object.values(rows), split }
  })

test('an empty case offers what cases usually start with, and a tile inserts and opens it', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const entry = await emptyCase(page)
  await page.goto(`/admin/projects/projects/update/${entry.id}`)
  await syncLV(page)

  const welcome = page.getByTestId('blocks-welcome')
  await expect(welcome).toBeVisible()
  const tiles = welcome.getByTestId('starting-module')
  await expect(tiles).toHaveCount(4)

  // Heading came first in three of the six cases.
  const first = tiles.nth(0)
  await expect(first).toContainText('Heading')
  await expect(first).toHaveAttribute('data-first-count', '3')
  await expect(first).toHaveAttribute('data-of', '6')
  await expect(first).not.toHaveAttribute('data-container-ref', /.+/)
  await expect(first.getByTestId('starting-module-count')).toBeVisible()

  // The container is counted with its first module, and labelled.
  const second = tiles.nth(1)
  await expect(second).toContainText('Single Image with Caption')
  await expect(second).toContainText('Wide section')
  await expect(second).toHaveAttribute('data-first-count', '2')
  await expect(second).toHaveAttribute('data-container-ref', /^local:\d+$/)

  await expect(tiles.nth(2)).toContainText('Rich Text Article')
  await expect(tiles.nth(2)).toHaveAttribute('data-first-count', '1')
  await expect(tiles.nth(0)).toHaveAttribute('data-source', 'first')
  // The fourth fills in from overall use, without a count.
  await expect(tiles.nth(3)).toContainText('Example module')
  await expect(tiles.nth(3)).toHaveAttribute('data-source', 'used')
  await expect(tiles.nth(3).getByTestId('starting-module-count')).toHaveCount(0)

  // The other ways to start sit with them; the plus stays. Build with AI is
  // in the card, not also by the label.
  await expect(welcome.getByTestId('all-modules')).toBeVisible()
  await expect(welcome.getByTestId('build-with-ai')).toHaveAttribute('target', '_blank')
  await expect(page.locator('.block-field-assistant')).toHaveCount(0)
  await expect(page.locator('.blocks-wrapper .block-plus').last()).toBeVisible()
  await page.screenshot({ path: testInfo.outputPath('empty-block-field-desktop.png'), fullPage: true })

  // Four in a row, with long names that wrap between words only.
  expect(await tileLayout(tiles)).toEqual({ rows: [4], split: [] })

  await page.setViewportSize({ width: 390, height: 844 })
  await welcome.scrollIntoViewIfNeeded()
  expect(await noOverflow(page)).toBeLessThanOrEqual(0)
  // Two to a row.
  const [a, b] = await Promise.all([tiles.nth(0).boundingBox(), tiles.nth(1).boundingBox()])
  expect(a.x + a.width).toBeLessThanOrEqual(390)
  expect(b.x + b.width).toBeLessThanOrEqual(390)
  expect(await tileLayout(tiles)).toEqual({ rows: [2, 2], split: [] })
  await page.screenshot({ path: testInfo.outputPath('empty-block-field-mobile.png'), fullPage: true })
  await page.setViewportSize({ width: 1440, height: 1000 })
  // The names were changed in the page only; it is reloaded before going on.
  await page.reload()
  await syncLV(page)

  await first.click()
  await syncLV(page)
  await expect(welcome).toHaveCount(0)
  const blocks = page.locator('#block-field-blocks > [data-uid]')
  await expect(blocks).toHaveCount(1)
  const block = blocks.first().locator('.base-block').first()
  await expect(block).not.toHaveClass(/collapsed/)
  await expect(block.locator('[data-block-type="module"]').first()).toBeVisible()
  await expect(block).toContainText('Heading')

  // With a block, Build with AI moves to the field's label.
  await expect(page.locator('.block-field-assistant').getByTestId('build-with-ai')).toBeVisible()
  await expect(page.getByTestId('build-with-ai')).toHaveCount(1)
})

test('a tile whose module starts in a container inserts both', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const entry = await emptyCase(page)
  const url = `/admin/projects/projects/update/${entry.id}`
  await page.goto(url)
  await syncLV(page)

  await page.locator('[data-testid="starting-module"][data-container-ref]').first().click()
  await syncLV(page)

  const container = page.locator('#block-field-blocks > [data-uid] [data-block-type="container"]').first()
  await expect(container).toBeVisible()
  const child = container.locator('.block-children [data-block-type="module"]')
  await expect(child).toHaveCount(1)
  await expect(container).toContainText('Single Image with Caption')

  // Saved, the container keeps its module.
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/projects\/projects$/)
  await page.goto(url)
  await syncLV(page)
  const saved = page.locator('#block-field-blocks > [data-uid] [data-block-type="container"]').first()
  await expect(saved.locator('.block-children [data-block-type="module"]')).toHaveCount(1)
  await expect(page.getByTestId('blocks-welcome')).toHaveCount(0)
})

test('without content to count, pinned modules come first and the rest keep the picker order', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const article = await factory(page, 'E2eProject.SyncTest.Article', {
    title: 'Empty article', slug: `empty-article-${Date.now()}`, language: 'en', status: 'draft', year: 2026,
  })
  await page.goto(`/admin/sync_test/articles/update/${article.id}`)
  await syncLV(page)

  const welcome = page.getByTestId('blocks-welcome')
  const tiles = welcome.getByTestId('starting-module')
  await expect(tiles).toHaveCount(4)
  // `starts_with: ["rich-text-article"]` on the field.
  await expect(tiles.first()).toContainText('Rich Text Article')
  // Too little content: no counts.
  await expect(welcome.getByTestId('starting-module-count')).toHaveCount(0)
  await expect(welcome.locator('[data-source="order"]')).toHaveCount(4)

  // The rest follow the module picker, which opens from "All modules…".
  await welcome.getByTestId('all-modules').click()
  const picker = page.locator('#block-field-blocks-module-picker')
  await expect(picker.locator('.module-row').first()).toBeVisible()
  const pickerOrder = await picker.locator('.module-picker-group').filter({ hasNotText: /Recently used/ }).locator('.module-row').evaluateAll(rows =>
    rows.map(row => row.dataset.moduleRef),
  )
  const offered = await tiles.evaluateAll(rows => rows.map(row => row.dataset.moduleRef))
  expect(offered.slice(1)).toEqual(pickerOrder.filter(ref => ref !== offered[0]).slice(0, 3))
})

test('a new entry asks to be saved before Build with AI, and a copied block can be pasted first', async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/projects/projects/create')
  await syncLV(page)

  const welcome = page.getByTestId('blocks-welcome')
  const ai = welcome.getByTestId('build-with-ai')
  await expect(ai).toBeVisible()
  await expect(ai).toBeDisabled()
  await expect(welcome.locator('.blocks-welcome-hint')).toBeVisible()
  // Nothing is copied yet.
  await expect(welcome.getByTestId('paste-first-block')).toHaveCount(0)

  // Copy the first block of the front page…
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  const source = page.locator('.block').first()
  await source.locator('.block-action-dropdown > .block-action').first().click()
  await source.locator('.block-action-dropdown-content button', { hasText: 'Copy' }).click()
  await syncLV(page)

  // …and paste it into an empty case.
  const entry = await emptyCase(page)
  await page.goto(`/admin/projects/projects/update/${entry.id}`)
  await syncLV(page)
  const paste = page.getByTestId('paste-first-block')
  await expect(paste).toBeVisible()
  await paste.click()
  await syncLV(page)
  await expect(page.locator('#block-field-blocks > [data-uid]')).toHaveCount(1)
  await expect(page.getByTestId('blocks-welcome')).toHaveCount(0)
})
