import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// The fixture prepares, as a tool connected over MCP would, a proposal that
// copies a team member from one page to the top of the team on three others:
// two published (one Norwegian) and a draft. Once applied, the review still
// shows each copy once: what was applied, not the copy again on top of it.
// Each card links to its page on the site, or for the draft to its preview.

test('an applied proposal shows what it applied, and each card links to its page', async ({ page }, testInfo) => {
  test.setTimeout(120000)
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })

  const response = await page.request.post('/e2e/setup_fixtures/assistant-applied-copy')
  expect(response.ok()).toBe(true)

  await page.goto('/admin/assistant/connected')
  await syncLV(page)
  await page.locator('#assistant-connected-list').getByRole('link', { name: /project video for VG/ }).click()
  await syncLV(page)

  const review = page.locator('.assistant-proposal')
  const cards = review.locator('.assistant-card')
  await expect(cards).toHaveCount(4)
  const strategy = cards.nth(1)
  const strategi = cards.nth(2)
  const branding = cards.nth(3)

  const expectOrder = async () => {
    for (const card of [strategy, strategi]) {
      await expect(card.locator('.assistant-order li')).toHaveCount(3)
      await expect(card.locator('.assistant-order li.is-new')).toHaveCount(1)
      await expect(card.locator('.assistant-order li').first()).toHaveClass(/is-new/)
    }
    await expect(branding.locator('.assistant-order li')).toHaveCount(2)
    await expect(branding.locator('.assistant-order li.is-new')).toHaveCount(1)
  }

  const expectAddresses = async () => {
    const link = strategy.locator('a.assistant-address')
    await expect(link).toHaveAttribute('href', /^https?:\/\/[^/]+\/.*strategy-and-positioning-for-growing-companies$/)
    await expect(link).toHaveAttribute('target', '_blank')
    // The Norwegian page links to its own language's address.
    await expect(strategi.locator('a.assistant-address')).toHaveAttribute('href', /\/no\/prosjekter\/kategori\/strategi$/)
    await expect(branding.locator('a.assistant-address')).toHaveCount(0)
    await expect(branding.locator('.assistant-draft')).toBeVisible()
  }

  await expectOrder()
  await expectAddresses()

  await review.locator('button.assistant-apply').click()
  await expect(review.locator('.assistant-feedback.is-success')).toBeVisible({ timeout: 20000 })
  await expectOrder()
  await expectAddresses()

  // Coming back to it shows the same.
  await page.reload()
  await syncLV(page)
  await expectOrder()

  // The draft's card opens its saved page's preview in a new tab, as the
  // entry form's standalone preview does. The window the server asks for is
  // recorded here and opened, rather than left to the popup blocker.
  await page.evaluate(() => {
    window.open = url => {
      window.__opened = url
    }
  })
  await branding.locator('button.assistant-saved-preview').click()
  await expect.poll(() => page.evaluate(() => window.__opened)).toMatch(/^\/__livepreview\?key=.+&mode=standalone$/)
  const url = await page.evaluate(() => window.__opened)

  // The address is cut in the middle on a phone, and the card keeps its width.
  await page.setViewportSize({ width: 390, height: 844 })
  const overflow = await strategy.evaluate(card => card.scrollWidth - card.clientWidth)
  expect(overflow).toBeLessThanOrEqual(0)
  await page.screenshot({ path: testInfo.outputPath('assistant-applied-390.png'), fullPage: true })

  const opened = await page.goto(url)
  expect(opened.ok()).toBe(true)
  await expect(page.locator('body')).toContainText('Sommerro')

  expect(errors).toEqual([])
})
