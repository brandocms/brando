import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Issue #1996. The admin is essentially one large form application, so its
// form layer has to be accessible: a modal takes focus when it opens. The
// failed-save announcement and focus are in editor-motion.spec.js, driven in
// Norwegian; correcting the field: form_validation_a11y_test.exs.

test.describe('Modal focus management', () => {
  test('a modal announces itself as a dialog, takes focus, and gives it back', async ({ page }) => {
    await page.goto('/admin/config/content/modules')
    await syncLV(page)

    // Opened from the header's import/export menu; focus comes back to the
    // menu's button, since the menu item is gone once the menu closes.
    const opener = page.locator('#module-transfer-menu > summary')
    await opener.click()
    await page.getByRole('button', { name: /^Paste encoded modules/ }).click()

    const modal = page.locator('#module-import-modal')
    await expect(modal).toBeVisible()
    await expect(modal).toHaveAttribute('role', 'dialog')
    await expect(modal).toHaveAttribute('aria-modal', 'true')
    // The dialog is named by its own heading rather than by nothing at all.
    await expect(modal).toHaveAttribute('aria-labelledby', 'module-import-modal-title')
    await expect(page.locator('#module-import-modal-title')).toHaveText('Import modules')

    // Focus moved into the dialog, so Tab walks it rather than the page behind.
    await expect
      .poll(() =>
        modal.evaluate(el => el === document.activeElement || el.contains(document.activeElement))
      )
      .toBe(true)

    await page.keyboard.press('Escape')
    await expect(modal).not.toBeVisible()

    // ...and closing hands focus back to whatever opened it.
    await expect(opener).toBeFocused()
  })

  // Without motion a dialog closes inside the keystroke that closes it. Focus
  // returns once that key is up: on the opener earlier, the keystroke's own
  // activation would land there (Enter would open the dialog again).
  const openImport = async page => {
    await page.emulateMedia({ reducedMotion: 'reduce' })
    await page.goto('/admin/config/content/modules')
    await syncLV(page)
    const opener = page.locator('#module-transfer-menu > summary')
    await opener.click()
    await page.getByRole('button', { name: /^Paste encoded modules/ }).click()
    const modal = page.locator('#module-import-modal')
    await expect(modal).toBeVisible()
    // Escape is the dialog's own key handler: wait for focus to be inside
    await expect
      .poll(() => modal.evaluate(el => el.contains(document.activeElement)))
      .toBe(true)
    return { opener, modal }
  }

  const surface = (page, action) =>
    page.evaluate(action => {
      document.querySelector('#module-import-modal').dispatchEvent(
        new CustomEvent('b:ui-surface', { bubbles: true, detail: { kind: 'modal', action } })
      )
    }, action)

  test('without motion, focus returns once the closing key is released', async ({ page }) => {
    const { opener, modal } = await openImport(page)
    await page.keyboard.down('Escape')
    await expect(modal).not.toBeVisible()
    // Deliberate observation window: while the key is held, focus stays put
    await page.waitForTimeout(150)
    await expect(opener).not.toBeFocused()
    await page.keyboard.up('Escape')
    await expect(opener).toBeFocused()
  })

  // macOS sends no keyup for a key pressed with ⌘: a key whose release never
  // comes must not hold back a later, unrelated close.
  test('without motion, a key never released does not delay a later close', async ({ page }) => {
    const { opener, modal } = await openImport(page)
    await page.keyboard.down('F8')
    await modal.getByRole('button', { name: 'Close dialog', exact: true }).click()
    await expect(modal).not.toBeVisible()
    // Well inside the one-second cap a stale key would wait for
    await expect(opener).toBeFocused({ timeout: 500 })
    await page.keyboard.up('F8')
  })

  test('without motion, a dialog reopened and closed before focus returns still returns it', async ({ page }) => {
    const { opener, modal } = await openImport(page)
    await page.keyboard.down('Escape')
    await expect(modal).not.toBeVisible()
    // Reopened with nothing focused outside it, so it records no opener of its own
    await surface(page, 'show')
    await expect(modal).toBeVisible()
    await surface(page, 'hide')
    await expect(modal).not.toBeVisible()
    await page.keyboard.up('Escape')
    await expect(opener).toBeFocused()
  })
})
