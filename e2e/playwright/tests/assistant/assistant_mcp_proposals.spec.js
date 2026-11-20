import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Proposals from a tool connected over MCP have no conversation. The fixture
// prepares two the way BrandoMCP does (`Proposals.Tools`, as the admin, from
// "Claude Code"), about different pages, so the second does not replace the
// first; the Assistant lists them under "From connected tools",
// where one is reviewed, previewed and applied, and the other rejected.

test('reviews, applies and rejects proposals from a connected tool', async ({ page }, testInfo) => {
  test.setTimeout(120000)
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })

  const response = await page.request.post('/e2e/setup_fixtures/mcp-proposals')
  expect(response.ok()).toBe(true)

  // The Assistant shows how many wait, and opens the list.
  await page.goto('/admin/assistant')
  await syncLV(page)
  const link = page.locator('.assistant-connected-link')
  await expect(link.locator('.assistant-count')).toContainText('2')
  await link.click()
  await expect(page).toHaveURL(/\/admin\/assistant\/connected$/)
  await syncLV(page)

  const list = page.locator('#assistant-connected-list')
  await expect(list.locator('li')).toHaveCount(2)
  await expect(list.getByTestId('assistant-state-waiting')).toHaveCount(2)
  await expect(page.locator('#assistant-composer')).toHaveCount(0)

  // Review one: its origin is marked, and its page can be previewed.
  await list.getByRole('link', { name: /Retitle the MCP review page/ }).click()
  await expect(page).toHaveURL(/\/admin\/assistant\/connected\/[0-9a-f-]+$/)
  await syncLV(page)
  const review = page.locator('.assistant-proposal')
  await expect(review.locator('#assistant-origin .ai-proposal-label')).toContainText('Claude Code')
  await expect(review.locator('.assistant-card')).toHaveCount(1)
  await expect(review.locator('.assistant-card ins')).toContainText('MCP review, from Claude Code')
  await page.screenshot({ path: testInfo.outputPath('assistant-mcp-review.png'), fullPage: true })

  // The preview has an address: the card's Preview adds the entry to it, and
  // back and forward close and open the preview again.
  const reviewUrl = page.url()
  await review.locator('.assistant-card-preview').click()
  await expect(page).toHaveURL(/\?preview=Brando\.Pages\.Page:\d+$/)
  await expect(page.locator('.assistant-preview')).toBeVisible()
  await page.goBack()
  await expect(page).toHaveURL(reviewUrl)
  await expect(review.locator('.assistant-cards')).toBeVisible()
  await expect(page.locator('.assistant-preview')).toHaveCount(0)
  await page.goForward()
  await expect(page.locator('.assistant-preview')).toBeVisible()
  await page.locator('.assistant-back').click()
  await expect(page).toHaveURL(reviewUrl)
  await expect(review.locator('.assistant-cards')).toBeVisible()

  // A tool's `preview_url`: a bare `?preview` opens on the first entry's page.
  await page.goto(`${reviewUrl}?preview`)
  await syncLV(page)
  await expect(page.locator('.assistant-preview-tabs button[aria-current="true"] strong')).toHaveText('MCP review')
  await expect(page.locator('.assistant-frame-viewport iframe, .assistant-frame-state')).toBeVisible()
  await page.locator('.assistant-back').click()
  await expect(page).toHaveURL(reviewUrl)
  await expect(review.locator('.assistant-cards')).toBeVisible()

  await review.locator('button.assistant-apply').click()
  await expect(review.locator('.assistant-feedback.is-success')).toBeVisible({ timeout: 15000 })
  await expect(list.getByTestId('assistant-state-applied')).toHaveCount(1)
  await expect(list.getByTestId('assistant-state-waiting')).toHaveCount(1)

  // The entry has the new title.
  await review.locator('.assistant-receipt a').first().click()
  await syncLV(page)
  await expect(page.getByLabel('Title', { exact: true })).toHaveValue('MCP review, from Claude Code', { timeout: 15000 })

  // Reject the other: it leaves the list, and its page keeps its title.
  await page.goto('/admin/assistant/connected')
  await syncLV(page)
  await list.getByRole('link', { name: /Retitle the MCP rejected page/ }).click()
  await syncLV(page)
  await review.locator('button[phx-click="cancel_proposal"]').click()
  await expect(list.locator('li')).toHaveCount(1)
  await expect(list.getByTestId('assistant-state-waiting')).toHaveCount(0)
  await expect(review.locator('button.assistant-apply')).toHaveCount(0)

  // Nothing waits: the Assistant still links to the list, without a count.
  await page.goto('/admin/assistant')
  await syncLV(page)
  await expect(link).toBeVisible()
  await expect(link.locator('.assistant-count')).toHaveCount(0)

  await page.goto('/admin/pages')
  await syncLV(page)
  await expect(page.getByRole('link', { name: 'MCP rejected', exact: true })).toBeVisible()
  await expect(page.getByRole('link', { name: 'Should not be applied' })).toHaveCount(0)
  expect(errors).toEqual([])
})

// A proposal stored before the content type catalogue was checked names a
// global set. Its review is refused: the reason shows in its place, with
// Discard, and discarding it takes it off the list.
test('discards a proposal from a connected tool that can no longer be applied', async ({ page }) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))

  const response = await page.request.post('/e2e/setup_fixtures/mcp-unloadable-proposal')
  expect(response.ok()).toBe(true)

  await page.goto('/admin/assistant/connected')
  await syncLV(page)
  const list = page.locator('#assistant-connected-list')
  await expect(list.locator('li')).toHaveCount(1)
  await list.locator('a[data-proposal-id]').click()
  await expect(page).toHaveURL(/\/admin\/assistant\/connected\/[0-9a-f-]+$/)
  await syncLV(page)

  const unloadable = page.locator('#assistant-unloadable')
  await expect(unloadable.getByRole('alert')).toContainText('Brando.Sites.GlobalSet')
  await expect(page.locator('button.assistant-apply')).toHaveCount(0)

  await unloadable.locator('button[phx-click="cancel_proposal"]').click()
  await expect(unloadable).toHaveCount(0)
  await expect(page.locator('.assistant-connected-empty')).toBeVisible()
  expect(errors).toEqual([])
})

// The card's cover is shown about 700px wide: it takes the image's sizes,
// not the 400px square thumb, cropped to the card around its focal point.
test("a card's cover is sharp at the card's width", async ({ page }) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })

  const response = await page.request.post('/e2e/setup_fixtures/assistant-cover')
  expect(response.ok()).toBe(true)

  await page.goto('/admin/assistant/connected')
  await syncLV(page)
  await page.locator('#assistant-connected-list').getByRole('link', { name: /Add the harbour page/ }).click()
  await expect(page).toHaveURL(/\/admin\/assistant\/connected\/[0-9a-f-]+$/)
  await syncLV(page)

  const cover = page.locator('.assistant-card-cover img')
  // The E2E app's images have one size above the thumb: small, 700px.
  await expect(cover).toHaveAttribute('srcset', /\/small\/.+ 700w$/)
  await expect(cover).toHaveAttribute('style', 'object-position: 50% 40%;')
  await expect.poll(() => cover.evaluate(img => img.complete && img.naturalWidth)).toBeGreaterThanOrEqual(700)
  expect(await cover.evaluate(img => img.currentSrc)).not.toContain('/thumb/')
  // The image fills the 16:10 frame, so object-fit crops it there.
  expect(await cover.evaluate(img => img.clientHeight === img.parentElement.clientHeight)).toBe(true)
  expect(errors).toEqual([])
})

// A connected tool proposes the English version of a Norwegian synchronized
// article. Its card says what it creates and offers no publishing; applied,
// the translation opens as a draft in the source's group.
test('applies a proposal from a connected tool that creates a translation', async ({ page }) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))

  const response = await page.request.post('/e2e/setup_fixtures/mcp-create-translation')
  expect(response.ok()).toBe(true)

  await page.goto('/admin/assistant/connected')
  await syncLV(page)
  const list = page.locator('#assistant-connected-list')
  await expect(list.locator('li')).toHaveCount(1)
  await list.locator('a[data-proposal-id]').click()
  await expect(page).toHaveURL(/\/admin\/assistant\/connected\/[0-9a-f-]+$/)
  await syncLV(page)

  const review = page.locator('.assistant-proposal')
  const card = review.locator('.assistant-card')
  await expect(card).toHaveCount(1)
  await expect(card.getByTestId('assistant-action-create')).toBeVisible()
  await expect(card.getByTestId('assistant-create-translation')).toContainText('Fjordhuset')
  await expect(card.locator('.assistant-publish')).toHaveCount(0)
  await expect(card.locator('.assistant-card-preview')).toHaveCount(0)

  await review.locator('button.assistant-apply').click()
  await expect(review.locator('.assistant-feedback.is-success')).toBeVisible({ timeout: 15000 })

  // The receipt links to the new translation's form
  await review.locator('.assistant-receipt a').first().click()
  await syncLV(page)
  await expect(page.locator('input[name$="[title]"]').first()).toHaveValue('Fjordhuset', { timeout: 15000 })
  expect(errors).toEqual([])
})

// A connected tool translates the English version of a Norwegian
// synchronized article: its card shows each text's source above its
// translation, and the subtitle kept as it is. Applied, the translation's
// form holds the translated title.
test('reviews and applies a translation from a connected tool', async ({ page }, testInfo) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })

  const response = await page.request.post('/e2e/setup_fixtures/mcp-translate')
  expect(response.ok()).toBe(true)

  await page.goto('/admin/assistant/connected')
  await syncLV(page)
  const list = page.locator('#assistant-connected-list')
  await expect(list.locator('li')).toHaveCount(1)
  await list.locator('a[data-proposal-id]').click()
  await expect(page).toHaveURL(/\/admin\/assistant\/connected\/[0-9a-f-]+$/)
  await syncLV(page)

  const review = page.locator('.assistant-proposal')
  const card = review.locator('.assistant-card')
  await expect(card).toHaveCount(1)
  await expect(card.getByTestId('assistant-translate')).toBeVisible()

  const units = card.locator('.assistant-translation')
  const title = units.locator('[data-key="title"]')
  await expect(title.locator('.assistant-translation-source')).toHaveText('Fjordhuset')
  await expect(title.locator('ins')).toHaveText('The Fjord House')
  const subtitle = units.locator('[data-key="subtitle"]')
  await expect(subtitle).toHaveAttribute('data-reviewed', 'true')
  await expect(subtitle.locator('.assistant-translation-source')).toHaveText('Arkitektkontor')
  await expect(subtitle.locator('ins')).toHaveCount(0)
  // A translation is saved as its form saves it: it is not published here
  await expect(card.locator('.assistant-publish')).toHaveCount(0)
  await page.screenshot({ path: testInfo.outputPath('assistant-mcp-translate.png'), fullPage: true })

  await review.locator('button.assistant-apply').click()
  await expect(review.locator('.assistant-feedback.is-success')).toBeVisible({ timeout: 15000 })

  await review.locator('.assistant-receipt a').first().click()
  await syncLV(page)
  await expect(page.locator('input[name$="[title]"]').first()).toHaveValue('The Fjord House', { timeout: 15000 })
  expect(errors).toEqual([])
})
