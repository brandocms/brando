import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A link var's Default tab (Link settings in the var editor) is where its
// link dialog opens while the link is empty. The seeded Kulturslider module's
// `cta` var has no link in the module nor in the Kulturkalender page's blocks:
// saving the module with Content as the default moves those blocks' empty
// vars onto it, and a block added afterwards starts there.
test.describe('Link var default tab', () => {
  test.setTimeout(90000)

  async function setDefaultTabToContent(page) {
    await page.goto('/admin/config/content/modules')
    await page.getByRole('link', { name: 'Kulturslider', exact: true }).first().click()
    await syncLV(page)

    const tab = page.getByRole('tab', { name: /^Variables/ })
    await expect(async () => {
      await tab.click()
      await expect(tab).toHaveAttribute('aria-selected', 'true')
    }).toPass({ timeout: 15000 })
    await syncLV(page)

    await page.getByRole('button', { name: 'Edit variable cta', exact: true }).click()
    const varModal = page.locator('.modal').filter({ has: page.getByRole('tab', { name: 'Link settings' }) }).filter({ visible: true })
    await varModal.getByRole('tab', { name: 'Link settings', exact: true }).click()

    const defaultTab = varModal.locator('[id$="link_default_type-field-base"]')
    await expect(defaultTab.getByRole('radio', { name: 'URL', exact: true })).toBeChecked()
    await defaultTab.getByRole('radio', { name: 'Content', exact: true }).check()
    await syncLV(page)
    await varModal.getByRole('button', { name: 'Done' }).click()

    await page.getByTestId('submit').click()
    await expect(page).toHaveURL('/admin/config/content/modules')
  }

  async function expectOpensOnContent(page, block) {
    const field = block.locator('.brando-input').filter({ hasText: 'Call to action' })
    await expect(field.locator('.link-preview')).toHaveClass(/link-preview--empty/)
    await field.locator('.link-preview').click()

    const linkModal = page.locator('[id$="-link-config"]').filter({ visible: true })
    await expect(linkModal).toBeVisible()
    await expect(linkModal.getByRole('radio', { name: 'Content', exact: true })).toBeChecked()
    await expect(linkModal.locator('.identifier-picker-option').first()).toBeVisible()

    // A default, not a lock: the editor can still type a URL
    await linkModal.getByRole('radio', { name: 'URL', exact: true }).check()
    await syncLV(page)
    await expect(linkModal.getByRole('radio', { name: 'URL', exact: true })).toBeChecked()
    await expect(linkModal.getByRole('textbox', { name: 'URL', exact: true })).toBeVisible()
  }

  test('an existing block and a new block open an empty link on Content', async ({ page }) => {
    await setDefaultTabToContent(page)

    // The page's blocks were synced when the module was saved
    await page.goto('/admin/pages')
    await page.getByRole('link', { name: 'Kulturkalender', exact: true }).first().click()
    await syncLV(page)
    await expectOpensOnContent(page, page.locator('[data-module-id]').first())

    // A block added now is copied from the module
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill('Default tab')
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: 'GENERAL' }).click()
    await page.getByRole('button', { name: /^Kulturslider\b/ }).click()
    await syncLV(page)
    await expectOpensOnContent(page, page.locator('[data-module-id]').first())
  })
})
