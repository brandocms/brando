import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A gallery block may hold one image twice (imported content, a script reusing
// one upload). The editor must open it, and each placement is its own object
// with its own caption and alt text (#3617).
test.describe('Gallery block with a repeated image', () => {
  const openRepeatedGallery = async page => {
    await page.goto('/admin/pages')
    await syncLV(page)
    await page.getByRole('link', { name: 'Repeated gallery', exact: true }).click()
    await syncLV(page)
  }

  const showList = async gallery => {
    const list = gallery.getByRole('button', { name: 'List', exact: true })
    if ((await list.getAttribute('aria-pressed')) !== 'true') await list.click()
    await expect(list).toHaveAttribute('aria-pressed', 'true')
  }

  test('opens, and each placement keeps its own caption and alt text', async ({ page }) => {
    await page.request.post('/e2e/setup_fixtures/gallery-repeated-image')
    await openRepeatedGallery(page)

    const gallery = page.locator('.gallery-block')
    const objects = gallery.locator('.gallery-object')
    await expect(objects).toHaveCount(2)

    // Alt text for the second placement only
    await objects.nth(1).getByRole('button', { name: 'No alt text' }).click()
    const alt = gallery.locator('textarea.gallery-text-editor-input')
    await expect(alt).toBeFocused()
    await alt.fill('Second placement alt')
    await alt.press('Enter')
    await expect(alt).toHaveCount(0)
    await expect(objects.nth(1).getByRole('button', { name: 'Alt text', exact: true })).toBeVisible()
    await expect(objects.nth(0).getByRole('button', { name: 'No alt text' })).toBeVisible()

    await showList(gallery)
    await expect(gallery.locator('.gallery-block-list-title')).toHaveText(['First placement', 'Second placement'])
    await expect(objects.nth(0).locator('.gallery-block-list-alt')).toHaveClass(/is-missing/)
    await expect(objects.nth(1).locator('.gallery-block-list-alt')).toContainText('Second placement alt')

    // Saved and opened again, each placement still has its own
    await page.getByRole('button', { name: /^Save and close (⇧⌘S|Ctrl\+Shift\+S)$/ }).click()
    await expect(page).toHaveURL(/\/admin\/pages$/)
    await openRepeatedGallery(page)

    await expect(objects).toHaveCount(2)
    await showList(gallery)
    await expect(gallery.locator('.gallery-block-list-title')).toHaveText(['First placement', 'Second placement'])
    await expect(objects.nth(0).locator('.gallery-block-list-alt')).toHaveClass(/is-missing/)
    await expect(objects.nth(1).locator('.gallery-block-list-alt')).toContainText('Second placement alt')
  })
})
