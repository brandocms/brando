import { test, expect } from '../test-support/setupAuth'
import { baseURL } from '../test-support/e2eUrl'
import { syncLV, withRealMotion } from '../utils'

const settled = page => page.evaluate(() => Promise.allSettled(document.getAnimations()
  .filter(a => a.effect.getTiming().iterations !== Infinity).map(a => a.finished)))

const sampleExit = button => button.evaluate(el => new Promise(resolve => {
  el.click()
  setTimeout(() => {
    const login = document.querySelector('#application-login')
    const target = document.querySelector(login ? '.login-box' : '#navigation')
    const style = getComputedStyle(target)
    resolve({
      opacity: Number(style.opacity), x: new DOMMatrix(style.transform).m41,
      busy: login?.getAttribute('aria-busy'),
      spinner: login && getComputedStyle(document.querySelector('.login-container'), '::after').opacity,
    })
  }, 100)
}))

test('login reveals every action smoothly, then login and logout finish their exit before navigating', async ({ browser, sandboxUserAgent }, testInfo) => {
  const context = await browser.newContext({ baseURL, userAgent: sandboxUserAgent, viewport: { width: 1440, height: 1000 } })
  const page = await context.newPage()
  await withRealMotion(page)
  try {
    await page.emulateMedia({ reducedMotion: 'no-preference' })
    await page.addInitScript(() => {
      window.appEntrance = []
      const animate = Element.prototype.animate
      Element.prototype.animate = function (...args) {
        if (['admin', 'navigation'].includes(this.id)) {
          window.appEntrance.push({ id: this.id, opacity: Number(getComputedStyle(this).opacity) })
        }
        return animate.apply(this, args)
      }
      window.addEventListener('brando:login-revealing', () => {
        window.loginReveal = ['.login-actions', '.login-passkey-alternative'].map(selector => {
          const row = document.querySelector(selector)
          return { opacity: Number(getComputedStyle(row).opacity), animated: row.getAnimations().length > 0 }
        })
      })
    })
    await page.goto('/admin/login')
    await syncLV(page)
    await expect.poll(() => page.evaluate(() => window.loginReveal)).toEqual([
      { opacity: 0, animated: true }, { opacity: 0, animated: true },
    ])
    await expect(page.locator('.brando-versioning')).toHaveCount(0)
    await expect(page.getByText(/BRANDO CMS/)).toHaveCount(0)
    await settled(page)
    const button = page.getByTestId('login-button')
    await page.getByTestId('email').fill('admin@brandocms.com')
    await page.getByTestId('password').fill('brandocms')
    await page.keyboard.press('Tab')
    await page.keyboard.press('Tab')
    await expect(button).toBeFocused()
    const offset = await button.evaluate(el => {
      const text = document.createRange()
      text.selectNodeContents(el)
      const label = text.getBoundingClientRect()
      const button = el.getBoundingClientRect()
      return Math.abs(label.x + label.width / 2 - button.x - button.width / 2)
    })
    expect(offset).toBeLessThan(1)
    await page.screenshot({ path: testInfo.outputPath('login-focus.png') })

    const signingIn = await sampleExit(button)
    expect(signingIn.busy).toBe('true')
    expect(signingIn.opacity).toBeGreaterThan(0)
    expect(signingIn.opacity).toBeLessThan(1)
    expect(Number(signingIn.spinner)).toBeGreaterThan(0)
    await expect(page).toHaveURL('/admin')
    await syncLV(page)
    await settled(page)
    await expect(page.locator('#navigation')).toBeVisible()
    await expect(page.locator('#admin')).toHaveCSS('opacity', '1')
    expect(await page.evaluate(() => window.appEntrance)).toEqual([
      { id: 'navigation', opacity: 0 },
      { id: 'admin', opacity: 0 },
    ])

    await page.getByTestId('current-user').click()
    const signingOut = await sampleExit(page.getByTestId('logout'))
    expect(signingOut.opacity).toBeGreaterThan(0)
    expect(signingOut.opacity).toBeLessThan(1)
    expect(signingOut.x).toBeLessThan(0)
    await expect(page).toHaveURL('/admin/login')
    await syncLV(page)
    await settled(page)
    await expect(page.locator('.login-box')).toHaveCSS('opacity', '1')
    await expect(page.getByTestId('login-button')).toBeEnabled()
    // Logout still invalidates the session, rather than only changing screens.
    await page.goto('/admin')
    await expect(page).toHaveURL('/admin/login')

    // An unsuccessful POST returns an ordinary usable login, too.
    await syncLV(page)
    await page.getByTestId('email').fill('admin@brandocms.com')
    await page.getByTestId('password').fill('wrong-password')
    const failed = await sampleExit(page.getByTestId('login-button'))
    expect(failed.busy).toBe('true')
    expect(failed.opacity).toBeGreaterThan(0)
    expect(failed.opacity).toBeLessThan(1)
    await expect(page.locator('#application-login')).not.toHaveAttribute('aria-busy', 'true')
    await expect(page.getByTestId('login-button')).toBeEnabled()
  } finally {
    await context.close()
  }
})

test('reduced-motion login and logout use immediate native submissions', async ({ browser, sandboxUserAgent }) => {
  const context = await browser.newContext({ baseURL, userAgent: sandboxUserAgent, reducedMotion: 'reduce' })
  const page = await context.newPage()
  await withRealMotion(page)
  try {
    await page.goto('/admin/login')
    await syncLV(page)
    await page.getByTestId('email').fill('admin@brandocms.com')
    await page.getByTestId('password').fill('brandocms')
    expect(await page.getByTestId('login-button').evaluate(el => {
      el.click()
      return document.documentElement.classList.contains('auth-leaving')
    })).toBe(false)
    await expect(page).toHaveURL('/admin')
    await syncLV(page)
    await page.getByTestId('current-user').click()
    expect(await page.getByTestId('logout').evaluate(el => {
      el.click()
      return document.documentElement.classList.contains('auth-leaving')
    })).toBe(false)
    await expect(page).toHaveURL('/admin/login')
  } finally {
    await context.close()
  }
})

test('canceling logout during its exit keeps the current LiveView connected', async ({ page }) => {
  await withRealMotion(page)
  await page.emulateMedia({ reducedMotion: 'no-preference' })
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  await settled(page)
  await page.getByTestId('current-user').click()
  await page.getByTestId('logout').evaluate(el => {
    el.click()
    window.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))
  })
  await expect(page.locator('#navigation')).toHaveCSS('opacity', '1')
  await expect(page).toHaveURL('/admin/pages/update/1')
  // A client-only panel can still open after LiveView has been destroyed.
  // Share preview needs an actual server event and reply to open its alert.
  await page.getByRole('button', { name: 'More', exact: true }).click()
  await page.getByRole('button', { name: 'Share preview', exact: true }).click()
  await expect(page.getByRole('dialog', { name: 'Get shareable link', exact: true })).toBeVisible()
})
