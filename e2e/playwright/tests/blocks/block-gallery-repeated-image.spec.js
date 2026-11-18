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

  // Visibility alone allows a save before the hook has decoded the source
  const expectImageEditorReady = async page => {
    await expect(page.locator('#image-editor-hook')).toHaveAttribute('aria-busy', 'false', { timeout: 15000 })
    await expect(page.locator('#image-editor-dimensions')).toHaveText(/^[1-9]\d* × [1-9]\d*$/)
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

  // "Save as new copy" on one placement replaces that placement's image only.
  // It keeps its caption; the other placement keeps the image and its own.
  test('a new copy of one placement replaces only that placement', async ({ page }) => {
    test.setTimeout(120000)
    await page.request.post('/e2e/setup_fixtures/gallery-repeated-image')
    await openRepeatedGallery(page)

    const gallery = page.locator('.gallery-block')
    const objects = gallery.locator('.gallery-object')
    await expect(objects).toHaveCount(2)

    const firstImg = objects.nth(0).locator('.gallery-tile-square img')
    const secondImg = objects.nth(1).locator('.gallery-tile-square img')
    await expect(secondImg).toBeVisible()
    const original = await secondImg.getAttribute('src')
    await expect(firstImg).toHaveAttribute('src', original)

    await objects.nth(1).getByRole('button', { name: 'Edit image' }).click()
    await expect(page.locator('#image-editor-canvas')).toBeVisible({ timeout: 10000 })
    await expectImageEditorReady(page)
    await page.locator('#image-editor-save-new').click()
    await page.waitForSelector('#image-editor-drawer', { state: 'hidden', timeout: 10000 })
    await syncLV(page)

    await expect(secondImg).not.toHaveAttribute('src', original, { timeout: 20000 })
    await expect(objects).toHaveCount(2)
    await expect(firstImg).toHaveAttribute('src', original)

    await showList(gallery)
    await expect(gallery.locator('.gallery-block-list-title')).toHaveText(['First placement', 'Second placement'])

    // Saved and opened again, still one copy in the second placement only
    await page.getByRole('button', { name: /^Save and close (⇧⌘S|Ctrl\+Shift\+S)$/ }).click()
    await expect(page).toHaveURL(/\/admin\/pages$/)
    await openRepeatedGallery(page)

    await expect(objects).toHaveCount(2)
    await showList(gallery)
    await expect(gallery.locator('.gallery-block-list-title')).toHaveText(['First placement', 'Second placement'])
    const first = await objects.nth(0).locator('img').first().getAttribute('src')
    const second = await objects.nth(1).locator('img').first().getAttribute('src')
    expect(first).toContain('e2e-directory-')
    expect(second).not.toContain('e2e-directory-')
  })
})
