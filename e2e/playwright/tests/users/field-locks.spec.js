import { test, expect } from '../../test-support/setupAuth'
import { syncLV, confirmUploadFolder, keepDuplicateUploads, routeLiveSocket, dropConnection, restoreConnection } from '../../utils'

// The fields another editor is in are locked for us until they leave them:
// rich text, a multi-select's options, and an image, video or file field
// while its drawer is open, however the drawer closes. Nothing is saved.
test.describe('Field locks', () => {
  test.setTimeout(180000)

  const openProject = async (page) => {
    await page.goto('/admin/projects/projects')
    await syncLV(page)
    await page.getByRole('link', { name: 'Test Project Beta' }).click()
    await syncLV(page)
    await expect(page.getByLabel('Title', { exact: true })).toBeVisible()
    return new URL(page.url()).pathname
  }

  test('fields outside the text inputs lock while in use and unlock when left', async ({ page, secondUserPage }) => {
    const path = await openProject(page)
    await secondUserPage.goto(path)
    await syncLV(secondUserPage)

    const locks = secondUserPage.locator('.field-wrapper.field-locked')
    const locked = (name) =>
      secondUserPage.locator(`.field-wrapper.field-locked [data-field-presence="project[${name}]"]`)

    // Rich text
    const editor = page.locator('.tiptap-wrapper [contenteditable="true"]').first()
    await editor.click()
    await expect(locked('introduction')).toHaveCount(1, { timeout: 5000 })
    await page.getByLabel('Title', { exact: true }).click()
    await expect(locked('introduction')).toHaveCount(0, { timeout: 5000 })
    await page.getByLabel('Title', { exact: true }).blur()
    await expect(locks).toHaveCount(0, { timeout: 5000 })

    // A multi-select's options
    await page.locator('#project_project_categories-field-base').getByRole('button', { name: 'Select' }).click()
    await expect(locked('project_categories')).toHaveCount(1, { timeout: 5000 })
    await page.getByRole('button', { name: 'OK' }).click()
    await expect(locks).toHaveCount(0, { timeout: 5000 })

    // An image field, for each way its drawer closes
    const image = page.locator('#project_listing_image-media')
    await image.locator('input[type="file"]').setInputFiles('./fixtures/image.jpg')
    await confirmUploadFolder(page)
    await keepDuplicateUploads(page)
    await expect(image.locator('img')).toBeVisible({ timeout: 30000 })

    const imageDrawer = page.locator('#image-drawer')
    const done = imageDrawer.getByRole('button', { name: 'Done', exact: true })
    const alt = imageDrawer.locator('textarea, input[type="text"]').first()
    const closes = {
      Done: () => done.click(),
      Close: () => imageDrawer.getByRole('button', { name: 'Close', exact: true }).click(),
      // Escape closes the drawer the focus is in
      Escape: async () => {
        await alt.focus()
        await page.keyboard.press('Escape')
      },
      backdrop: () => page.locator('#image-drawer + .media-drawer-backdrop').click({ position: { x: 10, y: 10 } }),
    }

    for (const [how, close] of Object.entries(closes)) {
      await test.step(`closing the image drawer with ${how}`, async () => {
        await image.getByRole('button', { name: 'Configure', exact: true }).click()
        await expect(done).toBeInViewport()
        await expect(locked('listing_image')).toHaveCount(1, { timeout: 5000 })

        // The drawer's own inputs don't release the image field
        await alt.click()
        await alt.blur()
        await syncLV(page)
        await expect(locked('listing_image')).toHaveCount(1)

        await close()
        await expect(locks).toHaveCount(0, { timeout: 5000 })
        // The drawer slides out before it is hidden; a Configure during the
        // slide would toggle it shut again.
        await expect(imageDrawer).toBeHidden()
      })
    }

    // A video field
    const video = page.locator('#project_cover_video-media')
    await video.locator('input[type="file"]').setInputFiles('./fixtures/video.mp4')
    await expect(video).toHaveAttribute('data-asset-id', /\d+/, { timeout: 30000 })
    await video.getByRole('button', { name: 'Configure', exact: true }).click()
    await expect(locked('cover_video')).toHaveCount(1, { timeout: 5000 })
    await page.locator('#video-drawer').getByRole('button', { name: 'Done', exact: true }).click()
    await expect(locks).toHaveCount(0, { timeout: 5000 })

    // A file field
    const file = page.locator('#project_cover_file-media')
    await file.locator('input[type="file"]').setInputFiles('./fixtures/test.pdf')
    await expect(file).toHaveAttribute('data-asset-id', /\d+/, { timeout: 30000 })
    await file.getByRole('button', { name: 'Configure', exact: true }).click()
    await expect(locked('cover_file')).toHaveCount(1, { timeout: 5000 })
    await page.locator('#file-drawer').getByRole('button', { name: 'Close' }).click()
    await expect(locks).toHaveCount(0, { timeout: 5000 })

    // B received the uploads, unsaved
    for (const field of ['listing_image', 'cover_video', 'cover_file']) {
      await expect(secondUserPage.locator(`#project_${field}-media`)).toHaveAttribute('data-asset-id', /\d+/, { timeout: 10000 })
    }
  })

  // What B types while the connection is lost (sleep, a network change) is
  // B's newest edit: LiveView rejoins with a new process and recovers the
  // form, and A, who holds the older title, gets B's.
  test('typing done offline survives the reconnect', async ({ page, secondUserPage }) => {
    const path = await openProject(page)
    await routeLiveSocket(secondUserPage)
    await secondUserPage.goto(path)
    await syncLV(secondUserPage)

    const aTitle = page.getByLabel('Title', { exact: true })
    const bTitle = secondUserPage.getByLabel('Title', { exact: true })

    await aTitle.fill('Test Project Beta, A')
    await aTitle.blur()
    await expect(bTitle).toHaveValue('Test Project Beta, A', { timeout: 5000 })

    await dropConnection(secondUserPage)
    await bTitle.fill('Test Project Beta, typed offline')
    await restoreConnection(secondUserPage)

    await expect(bTitle).toHaveValue('Test Project Beta, typed offline')
    await expect(aTitle).toHaveValue('Test Project Beta, typed offline', { timeout: 10000 })
  })
})
