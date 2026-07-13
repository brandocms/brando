import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Save → reload persistence guards for video and map ref commits.
//
// Regression coverage for the missing `propagate: true` bug class in
// video_block.ex (select_video committing video_id) and map_block.ex
// (the "url" handler committing embed_url). Both are out-of-band media
// commits: without propagation the parent's cached form keeps the old
// (empty) FK/data, and a later block insert re-initialises the block
// from that stale cache — the media LOOKS attached in the editor but is
// gone after save + reload.
test.describe('Video and map block save persistence', () => {
  test.describe.configure({ mode: 'serial' })

  const createPage = async (page, title, uri) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill(title)
    await page.getByLabel('URI').fill(uri)
  }

  // The bottom "Add block" (append) button and per-block gap "+" share the
  // same label; the append button is last in the DOM.
  //
  // Opening the picker right after a heavy re-render (the map iframe
  // mounting) can lose the click's push event when morphdom replaces the
  // button mid-click — the modal never opens and the spec used to hang until
  // the test timeout (the recurring flake in this file). Retry the open until
  // the picker content is actually on screen.
  const appendBlock = async (page, moduleName) => {
    const addBlock = page.getByRole('button', { name: 'Add block' }).last()
    const category = page.getByRole('button', { name: '05 LIVE PREVIEW TEST' })

    await expect(async () => {
      if (!(await category.isVisible())) {
        await addBlock.click({ timeout: 2000 })
      }
      await expect(category).toBeVisible({ timeout: 2000 })
    }).toPass({ timeout: 20000 })

    await category.click()
    await page.getByRole('button', { name: moduleName }).click()
    await syncLV(page)
  }

  const saveAndReopen = async (page, title) => {
    await page.getByRole('button', { name: 'Save' }).click()
    await expect(page).not.toHaveURL(/\/create$/, { timeout: 30000 })
    await syncLV(page)
    await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })

    await page.getByRole('link', { name: `${title} →` }).click()
    await syncLV(page)
  }

  test('video picked from the picker survives insert + save + reload', async ({ page }) => {
    test.setTimeout(120000)

    await createPage(page, 'Persist Video Test', 'persist-video-test')
    await appendBlock(page, 'Video Player')

    // Pick the seeded "Test Video" from the video picker drawer — this is
    // the select_video out-of-band video_id commit.
    await page.getByRole('button', { name: 'Select or create video' }).click()
    await syncLV(page)
    const videoRow = page.locator('.video-picker__video', { hasText: 'Test Video' }).first()
    await expect(videoRow).toBeVisible({ timeout: 10000 })
    await videoRow.click()
    await syncLV(page)

    // The block header shows the attached video's remote id.
    await expect(page.locator('.video-block')).toContainText('dQw4w9WgXcQ', { timeout: 10000 })

    // Stale-cache regression trigger: inserting another block re-initialises
    // siblings from the parent's cached forms — this must not wipe video_id.
    await appendBlock(page, 'Styled Header')

    await saveAndReopen(page, 'Persist Video Test')

    // The video must still be attached after a full round-trip through the DB.
    await expect(page.locator('.video-block')).toContainText('dQw4w9WgXcQ', { timeout: 20000 })
  })

  test('map embed URL survives insert + save + reload', async ({ page }) => {
    test.setTimeout(120000)

    await createPage(page, 'Persist Map Test', 'persist-map-test')
    await appendBlock(page, 'Map Embed')

    // Configure the map — the MapURLParser hook parses the pasted embed code
    // and pushes the "url" event (the out-of-band embed_url commit), then
    // auto-closes the config modal.
    await page.getByRole('button', { name: 'Configure map block' }).click()
    const mapModal = page.locator('[id$="_config"]:visible')
    await expect(mapModal).toBeVisible({ timeout: 5000 })
    await mapModal
      .locator('textarea')
      .fill(
        '<iframe src="https://www.google.com/maps/embed?pb=!1m18!1m12!1m3!1d2000" width="600" height="450"></iframe>'
      )
    await mapModal.getByRole('button', { name: 'Get map info' }).click()
    await syncLV(page)

    await expect(page.locator('.map-block iframe')).toBeVisible({ timeout: 10000 })

    // Stale-cache regression trigger.
    await appendBlock(page, 'Styled Header')

    await saveAndReopen(page, 'Persist Map Test')

    // The embed must still be attached after a full round-trip through the DB.
    const iframe = page.locator('.map-block iframe')
    await expect(iframe).toBeVisible({ timeout: 20000 })
    await expect(iframe).toHaveAttribute('src', /google\.com\/maps\/embed/)
  })
})
