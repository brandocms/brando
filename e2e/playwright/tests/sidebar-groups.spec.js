import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'

// Configuration's sidebar submenu lists its screens in groups, each labelled
// by a small heading (#3102). Driven in Norwegian, so the locators name the
// translated labels. Which groups a limited user sees is a LiveView test
// (test/brando_admin/live/nav_groups_test.exs).

test.beforeEach(async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
  await page.setViewportSize({ width: 1440, height: 1200 })
})

test('the groups open and close with Configuration, and their links work', async ({ page }) => {
  await page.goto('/admin')
  await syncLV(page)

  const nav = page.locator('#nav')
  const blocks = nav.getByRole('group', { name: 'Byggeklosser' })
  await expect(blocks).toBeHidden()

  await nav.locator('[data-nav-expand]').filter({ hasText: 'Konfigurasjon' }).click()

  for (const name of ['Nettsted', 'Publisering', 'Byggeklosser', 'Drift']) {
    await expect(nav.getByRole('group', { name })).toBeVisible()
    await expect(nav.getByRole('heading', { name, level: 4 })).toBeVisible()
  }

  await blocks.getByRole('link', { name: 'Blokkmoduler' }).click()
  await expect(page).toHaveURL('/admin/config/content/modules')
  await syncLV(page)
  await expect(blocks.getByRole('link', { name: 'Blokkmoduler' })).toHaveClass(/active/)

  // Closed, the headings leave with the links
  await nav.locator('[data-nav-expand]').filter({ hasText: 'Konfigurasjon' }).click()
  await expect(nav.getByRole('heading', { name: 'Byggeklosser', level: 4 })).toBeHidden()
  await expect(blocks.getByRole('link', { name: 'Blokkmoduler' })).toBeHidden()
  // and so do the groups, rather than staying as empty named groups
  for (const name of ['Nettsted', 'Publisering', 'Byggeklosser', 'Drift']) {
    await expect(nav.getByRole('group', { name })).toHaveCount(0)
  }

  // Opened again, they are back
  await nav.locator('[data-nav-expand]').filter({ hasText: 'Konfigurasjon' }).click()
  await expect(nav.getByRole('group', { name: 'Byggeklosser' })).toBeVisible()
  await expect(blocks.getByRole('link', { name: 'Blokkmoduler' })).toBeVisible()
})

test('the content language picker slides up and fades both ways', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'no-preference' })
  await page.goto('/admin')
  await syncLV(page)
  await page.evaluate(() => {
    document.body.removeAttribute('data-env')
    window.languageMotion = {}
    window.languageTrigger = document.querySelector('.current-language')
    const animate = Element.prototype.animate
    Element.prototype.animate = function (...args) {
      const animation = animate.apply(this, args)
      if (this.id === 'content-language-options') {
        animation.pause()
        const samples = [0, 100, animation.effect.getComputedTiming().duration].map(time => {
          animation.currentTime = time
          return {
            height: this.closest('.content-language-selector').getBoundingClientRect().height,
            buttonBottom: window.languageTrigger.getBoundingClientRect().bottom,
            opacity: Number(getComputedStyle(this).opacity),
          }
        })
        window.languageMotion[args[0][0].opacity === 0 ? 'enter' : 'leave'] = samples
        animation.currentTime = 0
        animation.play()
      }
      return animation
    }
  })
  const trigger = page.locator('.content-language-selector .current-language')
  const picker = page.locator('#content-language-options')
  await trigger.click()
  await expect(trigger).toHaveAttribute('aria-expanded', 'true')
  const enter = await page.evaluate(() => window.languageMotion.enter)
  expect(enter[1].height).toBeGreaterThan(enter[0].height)
  expect(enter[1].height).toBeLessThan(enter[2].height)
  expect(enter.every(sample => sample.buttonBottom === enter[0].buttonBottom)).toBe(true)
  expect(await page.evaluate(() => window.languageTrigger === document.querySelector('.current-language'))).toBe(true)
  await expect(picker).toHaveCSS('opacity', '1')
  await expect(picker).toHaveCSS('display', 'flex')

  await trigger.click()
  await expect(picker).toHaveCount(0)
  await expect(trigger).toHaveAttribute('aria-expanded', 'false')
  const leave = await page.evaluate(() => window.languageMotion.leave)
  expect(leave[1].height).toBeLessThan(leave[0].height)
  expect(leave[1].height).toBeGreaterThan(leave[2].height)
  expect(leave[2].height).toBeCloseTo(enter[0].height, 0)
  expect(leave.every(sample => sample.buttonBottom === leave[0].buttonBottom)).toBe(true)

  await page.emulateMedia({ reducedMotion: 'reduce' })
  await trigger.click()
  await expect(picker).toBeVisible()
  expect(await picker.evaluate(el => el.getAnimations().length)).toBe(0)
  await trigger.click()
  await expect(picker).toHaveCount(0)
})
