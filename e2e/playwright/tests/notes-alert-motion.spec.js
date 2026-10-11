import { test, expect } from '../test-support/setupAuth'
import { syncLV } from '../utils'

test.beforeEach(async ({ page }) => {
  await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')
  await page.emulateMedia({ reducedMotion: 'no-preference' })
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  await page.evaluate(() => document.body.removeAttribute('data-env'))
})

async function sharePreview(page) {
  await page.getByRole('button', { name: 'Mer', exact: true }).click()
  await page.getByRole('button', { name: 'Del forhåndsvisning', exact: true }).click()
  const dialog = page.getByRole('dialog', { name: 'Delbar link', exact: true })
  await expect(dialog).toBeVisible()
  await expect.poll(() => dialog.evaluate(el => Number(getComputedStyle(el, '::backdrop').opacity))).toBe(1)
  return dialog
}

for (const action of ['OK', 'backdrop', 'Escape']) {
  test(`share-preview alert fades its panel and backdrop when closed with ${action}`, async ({ page }) => {
    const dialog = await sharePreview(page)
    await dialog.evaluate((el, action) => {
      window.alertExitSample = null
      el.addEventListener(action === 'Escape' ? 'cancel' : 'click', () => {
        setTimeout(() => {
          window.alertExitSample = {
            connected: el.isConnected,
            open: el.open,
            panel: Number(getComputedStyle(el).opacity),
            backdrop: Number(getComputedStyle(el, '::backdrop').opacity)
          }
        }, 80)
      }, { once: true })
    }, action)

    if (action === 'OK') await dialog.getByRole('button', { name: 'OK', exact: true }).click()
    else if (action === 'Escape') await page.keyboard.press('Escape')
    else await page.mouse.click(5, 5)

    await expect.poll(() => page.evaluate(() => window.alertExitSample)).not.toBeNull()
    const exit = await page.evaluate(() => window.alertExitSample)
    expect(exit.connected).toBe(true)
    expect(exit.open).toBe(true)
    expect(exit.panel).toBeGreaterThan(0)
    expect(exit.panel).toBeLessThan(1)
    expect(exit.backdrop).toBeGreaterThan(0)
    expect(exit.backdrop).toBeLessThan(1)
    await expect(dialog).toHaveCount(0)
  })
}

test('shared alerts close immediately with reduced motion', async ({ page }) => {
  await page.emulateMedia({ reducedMotion: 'reduce' })
  const dialog = await sharePreview(page)
  expect(await dialog.evaluate(el => {
    el.querySelector('button').click()
    return el.open
  })).toBe(false)
  await expect(dialog).toHaveCount(0)
})

test('confirmation keeps the first decision and performs its action once after closing', async ({ page }) => {
  // Exercise the real delegated data-confirm handler without deleting a fixture.
  await page.evaluate(() => {
    window.confirmedActions = 0
    const button = document.createElement('button')
    button.id = 'motion-confirm-action'
    button.dataset.confirm = 'Bekreft handlingen'
    button.dataset.confirmOk = 'Fortsett'
    button.dataset.confirmCancel = 'Avbryt'
    button.textContent = 'Bekreft handlingen'
    button.addEventListener('click', () => { window.confirmedActions++ })
    document.body.appendChild(button)
    button.click()
  })
  const dialog = page.getByRole('dialog', { name: 'Bekreft handlingen', exact: true })
  await expect.poll(() => dialog.evaluate(el => Number(getComputedStyle(el).opacity))).toBe(1)
  const during = await dialog.evaluate(el => {
    el.querySelector('.is-primary').click()
    el.querySelector('.is-primary').click()
    el.dispatchEvent(new Event('cancel', { cancelable: true }))
    return { open: el.open, actions: window.confirmedActions }
  })
  expect(during).toEqual({ open: true, actions: 0 })
  await expect(dialog).toHaveCount(0)
  await expect.poll(() => page.evaluate(() => window.confirmedActions)).toBe(1)
})

for (const width of [1440, 390]) {
  test(`Notes slides in and out at ${width}px and retains a draft through reversal`, async ({ page }) => {
    await page.setViewportSize({ width, height: 1000 })
    const trigger = page.locator('.form-tool-notes')
    const panel = page.locator('.notes-panel')
    const inner = panel.locator('.notes-panel-inner')
    await expect(panel).toBeHidden()

    const sampleAfterClick = button => button.evaluate(el => new Promise(resolve => {
      el.click()
      setTimeout(() => {
        const panel = document.querySelector('.notes-panel')
        const box = panel.getBoundingClientRect()
        resolve({ width: box.width, x: box.x, opacity: Number(getComputedStyle(panel.querySelector('.notes-panel-inner')).opacity) })
      }, 80)
    }))
    const opening = await sampleAfterClick(trigger)
    expect(opening.opacity).toBeGreaterThan(0)
    expect(opening.opacity).toBeLessThan(1)
    if (width > 768) {
      expect(opening.width).toBeGreaterThan(0)
      expect(opening.width).toBeLessThan(380)
    } else {
      expect(opening.x).toBeGreaterThan(0)
      expect(opening.x).toBeLessThan(width)
    }
    await expect(inner).toHaveCSS('opacity', '1')
    await panel.getByRole('button', { name: 'Notat på oppføringen', exact: true }).click()
    const draft = panel.locator('.note-composer textarea')
    await draft.fill('Behold dette utkastet')

    const closing = await sampleAfterClick(panel.getByRole('button', { name: 'Lukk notater', exact: true }))
    expect(closing.opacity).toBeGreaterThan(0)
    expect(closing.opacity).toBeLessThan(1)
    if (width > 768) {
      expect(closing.width).toBeGreaterThan(0)
      expect(closing.width).toBeLessThan(380)
    } else {
      expect(closing.x).toBeGreaterThan(0)
      expect(closing.x).toBeLessThan(width)
    }
    await expect(panel).toBeHidden()
    await expect(trigger).toBeFocused()

    await trigger.click()
    await expect(inner).toHaveCSS('opacity', '1')
    // A second toggle reverses the closing transition from its painted position.
    await trigger.evaluate(el => new Promise(resolve => {
      el.click()
      setTimeout(() => { el.click(); resolve() }, 60)
    }))
    await expect(inner).toHaveCSS('opacity', '1')
    await expect(draft).toHaveValue('Behold dette utkastet')
    await expect(trigger).toHaveAttribute('aria-expanded', 'true')

    await page.emulateMedia({ reducedMotion: 'reduce' })
    await panel.getByRole('button', { name: 'Lukk notater', exact: true }).click()
    await expect(panel).toBeHidden({ timeout: 150 })
    await trigger.click()
    await expect(inner).toHaveCSS('opacity', '1', { timeout: 150 })
  })
}
