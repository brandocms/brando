import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A link var's entry can be let go of: clicking the chosen entry again
// deselects it, and switching the link to URL clears it, so switching back to
// Content shows none chosen. The seeded Kulturkalender page's Kulturslider
// blocks have an empty `cta` link ("Call to action").
test.describe('Clearing a link var', () => {
  test.setTimeout(90000)

  async function openPage(page) {
    await page.goto('/admin/pages')
    await page.getByRole('link', { name: 'Kulturkalender', exact: true }).first().click()
    await syncLV(page)
    return page.locator('[data-module-id]').first().locator('.brando-input').filter({ hasText: 'Call to action' })
  }

  async function openLink(page, field) {
    await field.locator('.link-preview').click()
    const modal = page.locator('[id$="-link-config"]').filter({ visible: true })
    await expect(modal).toBeVisible()
    return modal
  }

  async function showContent(page, modal) {
    await modal.getByRole('radio', { name: 'Content', exact: true }).check()
    await syncLV(page)
    await modal.getByRole('button', { name: /All content/ }).click()
    await expect(modal.getByRole('button', { name: /All content/ })).toHaveAttribute('aria-pressed', 'true')
  }

  test('clicking the chosen entry again, or switching to URL, clears it', async ({ page }) => {
    const field = await openPage(page)
    await expect(field.locator('.link-preview')).toHaveClass(/link-preview--empty/)

    const modal = await openLink(page, field)
    await showContent(page, modal)

    const entry = modal.locator('.identifier-options .identifier').first()
    const chosen = modal.locator('.identifier-options .identifier[aria-pressed="true"]')

    await entry.click()
    await syncLV(page)
    await expect(entry).toHaveAttribute('aria-pressed', 'true')
    await expect(field.locator('.link-preview')).not.toHaveClass(/link-preview--empty/)

    // The chosen entry, clicked again, is let go of
    await entry.click()
    await syncLV(page)
    await expect(chosen).toHaveCount(0)
    await expect(field.locator('.link-preview')).toHaveClass(/link-preview--empty/)

    // Chosen again, then the link switched to URL and back: none chosen
    await entry.click()
    await syncLV(page)
    await expect(entry).toHaveAttribute('aria-pressed', 'true')

    await modal.getByRole('radio', { name: 'URL', exact: true }).check()
    await syncLV(page)
    await expect(modal.getByRole('textbox', { name: 'URL', exact: true })).toHaveValue('')
    await expect(field.locator('.link-preview')).toHaveClass(/link-preview--empty/)

    await showContent(page, modal)
    await expect(entry).toBeVisible()
    await expect(chosen).toHaveCount(0)

    // Saved as no link: the page holds no entry for it either
    await modal.getByRole('radio', { name: 'URL', exact: true }).check()
    await syncLV(page)
    await modal.getByRole('button', { name: 'Done' }).click()
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })

    const saved = await openPage(page)
    await expect(saved.locator('.link-preview')).toHaveClass(/link-preview--empty/)
    const reopened = await openLink(page, saved)
    await showContent(page, reopened)
    await expect(reopened.locator('.identifier-options .identifier').first()).toBeVisible()
    await expect(reopened.locator('.identifier-options .identifier[aria-pressed="true"]')).toHaveCount(0)
  })
})
