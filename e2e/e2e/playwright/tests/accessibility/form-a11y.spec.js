import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Issue #1996. The admin is essentially one large form application, and before
// this it shipped a single ARIA attribute in the whole form layer: a submitted
// form announced nothing, a keyboard user was scrolled to an error they could
// not reach, and a modal opened with focus still behind it.

test.describe('Accessible form validation', () => {
  test('a failed save marks the field invalid, announces why, and moves focus to it', async ({
    page
  }) => {
    await page.goto('/admin/pages/create')
    await syncLV(page)

    // Required attributes are not validated while an entry is a draft, and a new
    // page starts as one — so publish it first, or the blank save succeeds.
    await page.locator('label').filter({ hasText: 'Published' }).click()

    const title = page.getByLabel('Title', { exact: true })

    // Nothing has been typed, so nothing is invalid yet — a blank create form
    // must not read as a form full of errors.
    await expect(title).not.toHaveAttribute('aria-invalid', 'true')
    // ...but it is announced as required.
    await expect(title).toHaveAttribute('aria-required', 'true')

    // The message container exists before it has anything to say: a live region
    // added together with its content is not reliably announced.
    const errors = page.locator('#page_title-error')
    await expect(errors).toHaveAttribute('role', 'alert')
    await expect(title).toHaveAttribute('aria-describedby', 'page_title-error')

    await page.getByTestId('submit').click()
    await syncLV(page)

    await expect(title).toHaveAttribute('aria-invalid', 'true')
    await expect(errors).not.toBeEmpty()

    // The caret lands in the offending control, not on the submit button —
    // and `aria-describedby` means arriving there reads the message out.
    await expect(title).toBeFocused()
  })

  test('correcting the field clears the announcement', async ({ page }) => {
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.locator('label').filter({ hasText: 'Published' }).click()

    const title = page.getByLabel('Title', { exact: true })
    await page.getByTestId('submit').click()
    await syncLV(page)
    await expect(title).toHaveAttribute('aria-invalid', 'true')

    await title.fill('An acceptable title')
    await syncLV(page)

    await expect(title).not.toHaveAttribute('aria-invalid', 'true')
    await expect(page.locator('#page_title-error')).toBeEmpty()
  })
})

test.describe('Modal focus management', () => {
  test('a modal announces itself as a dialog, takes focus, and gives it back', async ({ page }) => {
    await page.goto('/admin/config/content/modules')
    await syncLV(page)

    const opener = page.getByRole('button', { name: 'Import modules' })
    await opener.focus()
    await opener.click()

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
