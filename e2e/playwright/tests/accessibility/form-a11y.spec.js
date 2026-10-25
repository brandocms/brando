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
})
