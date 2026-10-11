import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// E2eProject.AssistantModel owns this paced, read-only script. It reports zero
// tokens and never calls a model provider, including when replayed manually.
const demo = 'Preview assistant animations'
const steps = '[data-assistant-step]'

const open = async page => {
  await page.goto('/admin/assistant')
  await syncLV(page)
}
const send = async page => {
  await page.getByLabel('Message', { exact: true }).fill(demo)
  await page.getByLabel('Message', { exact: true }).press('Enter')
}

test('thinking and new tool steps animate once, with complete accessible text and stable wrapping', async ({ page }, testInfo) => {
  await page.emulateMedia({ reducedMotion: 'no-preference' })
  await page.setViewportSize({ width: 1280, height: 800 })
  await page.addInitScript(() => {
    window.stepMotion = []
    const animate = Element.prototype.animate
    Element.prototype.animate = function (...args) {
      const animation = animate.apply(this, args)
      if (this.matches('.assistant-step-word')) {
        const step = this.closest('[data-assistant-step]')
        const sample = { id: step.id, text: step.textContent, start: Number(getComputedStyle(this).opacity) }
        window.stepMotion.push(sample)
        setTimeout(() => { sample.during = Number(getComputedStyle(this).opacity) }, 100)
      }
      return animation
    }
  })
  await open(page)
  await send(page)
  const progress = page.locator('.assistant-progress')
  await expect(progress).toBeVisible()
  await expect(progress.getByRole('button', { name: 'Stop', exact: true })).toBeEnabled()
  const spinner = page.locator('.assistant-spinner')
  expect(await spinner.evaluate(el => getComputedStyle(el, '::before').animationName)).toBe('assistant-spin')
  await expect(page.locator('.assistant-text').last()).toContainText('Animation preview complete', { timeout: 15000 })
  await expect(progress).toHaveCount(0)
  await expect(page.locator(steps)).toHaveCount(3)
  const samples = await page.evaluate(() => window.stepMotion)
  expect(new Set(samples.map(s => s.id)).size).toBe(3)
  expect(samples.every(s => s.start === 0)).toBe(true)
  expect(samples.some(s => s.during > 0 && s.during < 1)).toBe(true)
  expect(samples.some(s => s.text.includes('Searched for “Index” in Pages'))).toBe(true)
  await expect(page.locator('.assistant-step-term').first()).toHaveText('“Index”')
  await expect(page.locator('.assistant-cost')).toHaveCount(0)
  await expect(page.getByRole('heading', { name: 'No proposal yet' })).toBeVisible()
  await page.screenshot({ path: testInfo.outputPath('assistant-demo.png') })

  // A composer patch must not retype old steps. Replaying adds only new ones.
  await send(page)
  await expect(page.locator('.assistant-text')).toHaveCount(2, { timeout: 15000 })
  const replay = await page.evaluate(() => window.stepMotion)
  expect(new Set(replay.map(s => s.id)).size).toBe(6)
  expect(replay.filter(s => samples.some(old => old.id === s.id))).toEqual(samples)

  await page.reload()
  await syncLV(page)
  await expect(page.locator(steps)).toHaveCount(6)
  expect(await page.evaluate(() => window.stepMotion)).toEqual([])
  await page.evaluate(() => window.liveSocket.disconnect())
  await page.evaluate(() => window.liveSocket.connect())
  await syncLV(page)
  expect(await page.evaluate(() => window.stepMotion)).toEqual([])
  const conversation = new URL(page.url()).pathname
  await page.getByRole('link', { name: 'New conversation', exact: true }).click()
  await expect(page.locator(steps)).toHaveCount(0)
  await page.getByRole('button', { name: 'Recent conversations' }).click()
  await page.locator(`#assistant-history-list a[href="${conversation}"]`).click()
  await expect(page.locator(steps)).toHaveCount(6)
  expect(await page.evaluate(() => window.stepMotion)).toEqual([])
  expect(await page.locator('.assistant-messages').evaluate(el => el.scrollWidth - el.clientWidth)).toBeLessThanOrEqual(1)
})

for (const preference of ['system', 'admin']) {
  test(`assistant respects ${preference} reduced motion and Stop remains immediate`, async ({ page }) => {
    await page.emulateMedia({ reducedMotion: preference === 'system' ? 'reduce' : 'no-preference' })
    await open(page)
    if (preference === 'admin') await page.evaluate(() => {
      const meta = document.querySelector('meta[name="prefers_reduced_motion"]') || document.createElement('meta')
      meta.name = 'prefers_reduced_motion'
      meta.content = 'true'
      document.head.appendChild(meta)
      document.documentElement.dataset.reducedMotion = 'true'
    })
    await send(page)
    const progress = page.locator('.assistant-progress')
    await expect(progress).toBeVisible()
    expect(await page.locator('.assistant-spinner').evaluate(el => getComputedStyle(el, '::before').animationName)).toBe('none')
    await expect(page.locator(steps)).toHaveCount(1)
    expect(await page.locator(steps).first().evaluate(el => el.getAnimations({ subtree: true }).length)).toBe(0)
    await progress.getByRole('button', { name: 'Stop', exact: true }).click()
    await expect(progress).toContainText('Stopping')
    await expect(progress).toHaveCount(0, { timeout: 10000 })
    // The model call already in flight can record one last tool request before
    // the run observes cancellation. No subsequent model round should start.
    expect(await page.locator(steps).count()).toBeLessThanOrEqual(2)
    await expect(page.locator('.assistant-text').filter({ hasText: 'Animation preview complete' })).toHaveCount(0)
    await expect(page.getByRole('heading', { name: 'No proposal yet' })).toBeVisible()
  })
}
