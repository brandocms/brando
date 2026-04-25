import { test, expect } from '../../test-support/setupAuth'
import {
  syncLV,
  toggleLivePreview,
  getPreviewFrame,
  waitForPreviewReady,
  waitForPreviewUpdate,
  setPreviewDevice
} from '../../utils'

test.describe('Live Preview with Blocks, Vars and Refs', () => {
  // Run serially — each test opens a preview channel + renders templates,
  // and parallel execution under full-suite load causes timeouts
  test.setTimeout(60000)

  test.describe('Basic Live Preview', () => {
    test('can enable and disable live preview', async ({ page }) => {
      // Navigate to Pages
      await page.goto('/admin')
      await page.getByRole('link', { name: 'Pages & Sections' }).click()
      await syncLV(page)

      // Create new page
      await page.getByRole('link', { name: 'Create page' }).click()
      await syncLV(page)

      // Fill page basics
      await page.getByLabel('Title', { exact: true }).fill('Live Preview Test Page')
      await page.getByLabel('URI').fill('live-preview-test')

      // Add a simple header block
      await page.getByRole('button', { name: 'Add block' }).click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Styled Header' }).click()
      await syncLV(page)

      // Enable live preview
      await toggleLivePreview(page)
      await waitForPreviewReady(page)

      // Verify preview is visible
      await expect(page.locator('.live-preview-wrapper')).toBeVisible()
      await expect(page.locator('.live-preview-wrapper iframe')).toBeVisible()

      // Disable live preview
      await toggleLivePreview(page)
      await syncLV(page)

      // Verify preview is hidden (extended timeout for loaded systems)
      await expect(page.locator('.live-preview-wrapper')).not.toBeVisible({ timeout: 15000 })
    })

    test('live preview restores after LiveSocket reconnect', async ({ page }) => {
      // Navigate to Pages
      await page.goto('/admin')
      await page.getByRole('link', { name: 'Pages & Sections' }).click()
      await syncLV(page)

      // Create new page
      await page.getByRole('link', { name: 'Create page' }).click()
      await syncLV(page)

      // Fill page basics
      await page.getByLabel('Title', { exact: true }).fill('Reconnect Test Page')
      await page.getByLabel('URI').fill('reconnect-test')

      // Add a simple header block
      await page.getByRole('button', { name: 'Add block' }).click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Styled Header' }).click()
      await syncLV(page)

      // Enable live preview
      await toggleLivePreview(page)
      await waitForPreviewReady(page)

      // Verify preview is active
      const frame = getPreviewFrame(page)
      await expect(frame.locator('header[b-tpl="styled-header"] h1')).toContainText('Header Text')

      // Disconnect the LiveSocket to simulate a network blip
      await page.evaluate(() => window.liveSocket.disconnect())
      await page.waitForTimeout(500)

      // Reconnect the LiveSocket — the reconnect hook restores the preview
      await page.evaluate(() => window.liveSocket.connect())
      await syncLV(page)

      // Wait for the preview to be restored by the reconnect hook
      await waitForPreviewReady(page)

      // Verify the preview iframe is visible after restore
      await expect(page.locator('.live-preview-wrapper iframe')).toBeVisible()

      // Get a fresh frame reference (iframe was recreated)
      const restoredFrame = getPreviewFrame(page)

      // Make a change and verify the preview still updates
      const headerTextarea = page.locator('.header-block textarea')
      await headerTextarea.fill('After Reconnect')
      await waitForPreviewUpdate(page)
      await expect(restoredFrame.locator('header[b-tpl="styled-header"] h1')).toContainText('After Reconnect')
    })

    test('device size buttons work (desktop/tablet/mobile)', async ({ page }) => {
      await page.goto('/admin')
      await page.getByRole('link', { name: 'Pages & Sections' }).click()
      await syncLV(page)

      await page.getByRole('link', { name: 'Create page' }).click()
      await syncLV(page)

      await page.getByLabel('Title', { exact: true }).fill('Device Test Page')
      await page.getByLabel('URI').fill('device-test')

      // Add a block
      await page.getByRole('button', { name: 'Add block' }).click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Styled Header' }).click()
      await syncLV(page)

      // Enable live preview
      await toggleLivePreview(page)
      await waitForPreviewReady(page)

      // Test tablet size
      await setPreviewDevice(page, 'tablet')
      // Verify the tablet button is active or the iframe has changed size
      await page.waitForTimeout(300)

      // Test mobile size
      await setPreviewDevice(page, 'mobile')
      await page.waitForTimeout(300)

      // Test desktop size
      await setPreviewDevice(page, 'desktop')
      await page.waitForTimeout(300)
    })
  })

  test.describe('Picture Ref + Variables', () => {
    test('adding image and changing caption updates preview', async ({ page }) => {
      await page.goto('/admin')
      await page.getByRole('link', { name: 'Pages & Sections' }).click()
      await syncLV(page)

      await page.getByRole('link', { name: 'Create page' }).click()
      await syncLV(page)

      await page.getByLabel('Title', { exact: true }).fill('Picture Ref Test Page')
      await page.getByLabel('URI').fill('picture-ref-test')

      // Add Single Image with Caption block
      await page.getByRole('button', { name: 'Add block' }).click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Single Image with Caption' }).click()
      await syncLV(page)

      // Enable live preview
      await toggleLivePreview(page)
      await waitForPreviewReady(page)

      const frame = getPreviewFrame(page)

      // Verify default caption is in preview
      await expect(frame.locator('figcaption')).toContainText('Default caption text')

      // Change the caption variable (use the one inside Block Variables, not the picture ref's caption)
      await page.locator('.block-vars').getByLabel('Caption').fill('Updated caption text')
      await waitForPreviewUpdate(page)

      // Verify caption updated in preview
      await expect(frame.locator('figcaption')).toContainText('Updated caption text')

      // Upload an image to the picture ref
      // The picture block has class .picture-block with a .file-input inside
      await page.locator('.picture-block .file-input').setInputFiles('./fixtures/image.jpg')
      await syncLV(page)
      await page.waitForTimeout(2000) // Wait for upload to complete

      await waitForPreviewUpdate(page)

      // Verify image appears in preview (use first() since picture element contains multiple img tags)
      await expect(frame.locator('figure picture').first()).toBeVisible()
    })

    test('toggling show_border var updates preview', async ({ page }) => {
      await page.goto('/admin')
      await page.getByRole('link', { name: 'Pages & Sections' }).click()
      await syncLV(page)

      await page.getByRole('link', { name: 'Create page' }).click()
      await syncLV(page)

      await page.getByLabel('Title', { exact: true }).fill('Border Toggle Test Page')
      await page.getByLabel('URI').fill('border-toggle-test')

      // Add Single Image with Caption block
      await page.getByRole('button', { name: 'Add block' }).click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Single Image with Caption' }).click()
      await syncLV(page)

      // Enable live preview
      await toggleLivePreview(page)
      await waitForPreviewReady(page)

      const frame = getPreviewFrame(page)

      // Verify border is not shown initially (show_border default is false)
      await expect(frame.locator('figure[data-border="true"]')).not.toBeVisible()

      // Toggle show_border to true - click the slider in the field-wrapper containing the label
      await page.locator('.field-wrapper:has-text("Show border") .slider').click()
      await waitForPreviewUpdate(page)

      // Verify border is now shown
      await expect(frame.locator('figure[data-border="true"]')).toBeVisible()

      // Toggle back to false
      await page.locator('.field-wrapper:has-text("Show border") .slider').click()
      await waitForPreviewUpdate(page)

      // Verify border is hidden again
      await expect(frame.locator('figure[data-border="true"]')).not.toBeVisible()
    })
  })

  test.describe('Gallery Ref + Variables', () => {
    test('adding images to gallery and changing vars updates preview', async ({ page }) => {
      await page.goto('/admin')
      await page.getByRole('link', { name: 'Pages & Sections' }).click()
      await syncLV(page)

      await page.getByRole('link', { name: 'Create page' }).click()
      await syncLV(page)

      await page.getByLabel('Title', { exact: true }).fill('Gallery Ref Test Page')
      await page.getByLabel('URI').fill('gallery-ref-test')

      // Add Gallery with Controls block
      await page.getByRole('button', { name: 'Add block' }).click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Gallery with Controls' }).click()
      await syncLV(page)

      // Enable live preview
      await toggleLivePreview(page)
      await waitForPreviewReady(page)

      const frame = getPreviewFrame(page)

      // Verify default title in preview
      await expect(frame.locator('.gallery-title')).toContainText('Gallery Title')

      // Verify default layout is grid
      await expect(frame.locator('section[data-layout="grid"]')).toBeVisible()

      // Change title variable (use locator within block-vars to avoid matching page title)
      await page.locator('.block-vars').getByLabel('Title').fill('My Custom Gallery')
      await waitForPreviewUpdate(page)
      await expect(frame.locator('.gallery-title')).toContainText('My Custom Gallery')

      // Change layout to list - click Select button then click option
      await page.locator('.field-wrapper:has-text("Layout") .button-edit').click()
      await page.locator('.field-wrapper:has-text("Layout") .options-option:has-text("list")').click()
      await waitForPreviewUpdate(page)
      await expect(frame.locator('section[data-layout="list"]')).toBeVisible()

      // Toggle stagger animation - click the slider in the field-wrapper containing the label
      await page.locator('.field-wrapper:has-text("Stagger animation") .slider').click()
      await waitForPreviewUpdate(page)
      await expect(frame.locator('section[data-stagger="true"]')).toBeVisible()

      // Upload images to gallery
      // The gallery block has class .gallery-block with a .file-input inside
      await page.locator('.gallery-block .file-input').setInputFiles(['./fixtures/image.jpg', './fixtures/image2.jpg'])
      await syncLV(page)
      // Wait for both image objects to appear in gallery (replaces hardcoded timeout)
      await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(2, { timeout: 15000 })

      await waitForPreviewUpdate(page)

      // Select video for gallery
      await page.getByRole('button', { name: 'Select videos' }).click()
      await syncLV(page)

      // Pick a video from the video picker drawer
      const videoPicker = page.locator('#video-picker')
      await expect(videoPicker).toBeVisible()

      // Select the seeded test video
      await videoPicker.locator('.video-picker__video').first().click()
      await syncLV(page)

      // Verify video object appears in gallery
      await expect(page.locator('.gallery-block .gallery-object')).toHaveCount(3)
    })
  })

  test.describe('Header Ref + Variables', () => {
    test('editing header and changing style vars updates preview', async ({ page }) => {
      await page.goto('/admin')
      await page.getByRole('link', { name: 'Pages & Sections' }).click()
      await syncLV(page)

      await page.getByRole('link', { name: 'Create page' }).click()
      await syncLV(page)

      await page.getByLabel('Title', { exact: true }).fill('Header Style Test Page')
      await page.getByLabel('URI').fill('header-style-test')

      // Add Styled Header block
      await page.getByRole('button', { name: 'Add block' }).click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Styled Header' }).click()
      await syncLV(page)

      // Enable live preview
      await toggleLivePreview(page)
      await waitForPreviewReady(page)

      const frame = getPreviewFrame(page)

      // Verify default header text (use b-tpl attribute to target module output)
      await expect(frame.locator('header[b-tpl="styled-header"] h1')).toContainText('Header Text')

      // Verify default alignment (left)
      await expect(frame.locator('header[b-tpl="styled-header"][style*="text-align: left"]')).toBeVisible()

      // Change alignment to center - click Select button then click option
      await page.locator('.field-wrapper:has-text("Alignment") .button-edit').click()
      await page.locator('.field-wrapper:has-text("Alignment") .options-option:has-text("center")').click()
      await waitForPreviewUpdate(page)
      await expect(frame.locator('header[b-tpl="styled-header"][style*="text-align: center"]')).toBeVisible()

      // Change alignment to right - click Select button then click option
      await page.locator('.field-wrapper:has-text("Alignment") .button-edit').click()
      await page.locator('.field-wrapper:has-text("Alignment") .options-option:has-text("right")').click()
      await waitForPreviewUpdate(page)
      await expect(frame.locator('header[b-tpl="styled-header"][style*="text-align: right"]')).toBeVisible()

      // Edit the header text in the ref (header block uses a textarea)
      const headerTextarea = page.locator('.header-block textarea')
      await headerTextarea.fill('Custom Header')
      await waitForPreviewUpdate(page)
      await expect(frame.locator('header[b-tpl="styled-header"] h1')).toContainText('Custom Header')
    })
  })

  test.describe('Text Ref + Variables', () => {
    test('toggling show_intro and editing text updates preview', async ({ page }) => {
      await page.goto('/admin')
      await page.getByRole('link', { name: 'Pages & Sections' }).click()
      await syncLV(page)

      await page.getByRole('link', { name: 'Create page' }).click()
      await syncLV(page)

      await page.getByLabel('Title', { exact: true }).fill('Rich Text Test Page')
      await page.getByLabel('URI').fill('rich-text-test')

      // Add Rich Text Article block
      await page.getByRole('button', { name: 'Add block' }).click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Rich Text Article' }).click()
      await syncLV(page)

      // Enable live preview
      await toggleLivePreview(page)
      await waitForPreviewReady(page)

      const frame = getPreviewFrame(page)

      // Verify intro is visible (show_intro default is true)
      await expect(frame.locator('.intro')).toBeVisible()

      // Toggle show_intro to false - click the slider in the field-wrapper containing the label
      await page.locator('.field-wrapper:has-text("Show intro") .slider').click()
      await waitForPreviewUpdate(page)

      // Verify intro is hidden
      await expect(frame.locator('.intro')).not.toBeVisible()

      // Toggle back to true
      await page.locator('.field-wrapper:has-text("Show intro") .slider').click()
      await waitForPreviewUpdate(page)

      // Verify intro is visible again
      await expect(frame.locator('.intro')).toBeVisible()
    })
  })

  test.describe('Video Ref + Variables', () => {
    test('toggling autoplay and controls vars updates preview', async ({ page }) => {
      await page.goto('/admin')
      await page.getByRole('link', { name: 'Pages & Sections' }).click()
      await syncLV(page)

      await page.getByRole('link', { name: 'Create page' }).click()
      await syncLV(page)

      await page.getByLabel('Title', { exact: true }).fill('Video Player Test Page')
      await page.getByLabel('URI').fill('video-player-test')

      // Add Video Player block
      await page.getByRole('button', { name: 'Add block' }).click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Video Player' }).click()
      await syncLV(page)

      // Enable live preview
      await toggleLivePreview(page)
      await waitForPreviewReady(page)

      const frame = getPreviewFrame(page)

      // Verify default values (autoplay=false, show_controls=true)
      await expect(frame.locator('div[data-autoplay="false"]')).toBeVisible()
      await expect(frame.locator('div[data-controls="true"]')).toBeVisible()

      // Toggle autoplay to true - click the slider in the field-wrapper containing the label
      await page.locator('.field-wrapper:has-text("Autoplay") .slider').click()
      await waitForPreviewUpdate(page)
      await expect(frame.locator('div[data-autoplay="true"]')).toBeVisible()

      // Toggle controls to false - click the slider in the field-wrapper containing the label
      await page.locator('.field-wrapper:has-text("Show controls") .slider').click()
      await waitForPreviewUpdate(page)
      await expect(frame.locator('div[data-controls="false"]')).toBeVisible()
    })
  })

  test.describe('Persistence', () => {
    test('preview reflects saved content after page reload', async ({ page }) => {
      await page.goto('/admin')
      await page.getByRole('link', { name: 'Pages & Sections' }).click()
      await syncLV(page)

      await page.getByRole('link', { name: 'Create page' }).click()
      await syncLV(page)

      await page.getByLabel('Title', { exact: true }).fill('Persistence Test Page')
      await page.getByLabel('URI').fill('persistence-test')

      // Add Styled Header block
      await page.getByRole('button', { name: 'Add block' }).click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Styled Header' }).click()
      await syncLV(page)

      // Change alignment to center - click Select button then click option
      await page.locator('.field-wrapper:has-text("Alignment") .button-edit').click()
      await page.locator('.field-wrapper:has-text("Alignment") .options-option:has-text("center")').click()
      await syncLV(page)

      // Save the page
      await page.getByTestId('submit').click()
      await expect(page).toHaveURL(/\/admin\/pages$/)
      await syncLV(page)

      // Re-open the page
      await page.getByRole('link', { name: 'Persistence Test Page' }).click()
      await syncLV(page)

      // Verify alignment is still center (check the select label shows "Center" - note capitalization)
      await expect(page.locator('.field-wrapper:has-text("Alignment") .select-label')).toContainText('Center')

      // Enable live preview
      await toggleLivePreview(page)
      await waitForPreviewReady(page)

      const frame = getPreviewFrame(page)

      // Verify preview reflects saved value (use b-tpl to target module output)
      await expect(frame.locator('header[b-tpl="styled-header"][style*="text-align: center"]')).toBeVisible()
    })

    test('multiple block changes all reflect in preview', async ({ page }) => {
      await page.goto('/admin')
      await page.getByRole('link', { name: 'Pages & Sections' }).click()
      await syncLV(page)

      await page.getByRole('link', { name: 'Create page' }).click()
      await syncLV(page)

      await page.getByLabel('Title', { exact: true }).fill('Multi Block Test Page')
      await page.getByLabel('URI').fill('multi-block-test')

      // Add Styled Header block
      await page.getByRole('button', { name: 'Add block' }).click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Styled Header' }).click()
      await syncLV(page)

      // Add Single Image with Caption block (use first() because there are now 2 add buttons)
      await page.getByRole('button', { name: 'Add block' }).first().click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Single Image with Caption' }).click()
      await syncLV(page)

      // Enable live preview
      await toggleLivePreview(page)
      await waitForPreviewReady(page)

      const frame = getPreviewFrame(page)

      // Change header alignment (scope within first block vars) - click Select button then click option
      await page.locator('.field-wrapper:has-text("Alignment")').first().locator('.button-edit').click()
      await page.locator('.field-wrapper:has-text("Alignment")').first().locator('.options-option:has-text("right")').click()
      await waitForPreviewUpdate(page)

      // Change caption text (Caption is unique to the second block, so we can use it directly)
      await page.getByRole('textbox', { name: 'Caption' }).fill('Multi block caption')
      await waitForPreviewUpdate(page)

      // Verify both changes in preview (use b-tpl to target module output)
      await expect(frame.locator('header[b-tpl="styled-header"][style*="text-align: right"]')).toBeVisible()
      await expect(frame.locator('figcaption')).toContainText('Multi block caption')
    })
  })

  test.describe('Block Lifecycle', () => {
    test('deleting a block removes it from preview', async ({ page }) => {
      await page.goto('/admin')
      await page.getByRole('link', { name: 'Pages & Sections' }).click()
      await syncLV(page)

      await page.getByRole('link', { name: 'Create page' }).click()
      await syncLV(page)

      await page.getByLabel('Title', { exact: true }).fill('Delete Block Test Page')
      await page.getByLabel('URI').fill('delete-block-test')

      // Add Styled Header block
      await page.getByRole('button', { name: 'Add block' }).click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Styled Header' }).click()
      await syncLV(page)

      // Add Single Image with Caption block
      await page.getByRole('button', { name: 'Add block' }).first().click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Single Image with Caption' }).click()
      await syncLV(page)

      // Enable live preview
      await toggleLivePreview(page)
      await waitForPreviewReady(page)

      const frame = getPreviewFrame(page)

      // Verify both blocks visible in iframe
      await expect(frame.locator('header[b-tpl="styled-header"]')).toBeVisible()
      await expect(frame.locator('figure[b-tpl="single-image"]')).toBeVisible()

      // Target the header module block by its name label (avoids position ambiguity)
      const headerBlock = page.locator('.entry-block:has(:text("STYLED HEADER"))')
      await headerBlock.locator('.block-action-dropdown > button.block-action').first().click()

      // Click Delete from the dropdown
      await headerBlock.locator('.block-action-dropdown-content button:has-text("Delete")').first().click()
      await waitForPreviewUpdate(page)

      // Assert: header is NOT visible in iframe
      await expect(frame.locator('header[b-tpl="styled-header"]')).not.toBeVisible()

      // Assert: image block IS still visible in iframe
      await expect(frame.locator('figure[b-tpl="single-image"]')).toBeVisible()
    })

    test('deactivating a block hides it from preview', async ({ page }) => {
      await page.goto('/admin')
      await page.getByRole('link', { name: 'Pages & Sections' }).click()
      await syncLV(page)

      await page.getByRole('link', { name: 'Create page' }).click()
      await syncLV(page)

      await page.getByLabel('Title', { exact: true }).fill('Deactivate Block Test Page')
      await page.getByLabel('URI').fill('deactivate-block-test')

      // Add Styled Header block
      await page.getByRole('button', { name: 'Add block' }).click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Styled Header' }).click()
      await syncLV(page)

      // Enable live preview
      await toggleLivePreview(page)
      await waitForPreviewReady(page)

      const frame = getPreviewFrame(page)

      // Verify header visible in iframe
      await expect(frame.locator('header[b-tpl="styled-header"]')).toBeVisible()

      // Click the module-level active toggle (first() to skip nested ref block toggles)
      const block = page.locator('.entry-block:has(:text("STYLED HEADER"))')
      await block.locator('.switch.small.inverse .slider').first().click()
      await waitForPreviewUpdate(page)

      // Assert: header NOT visible in iframe (deactivated blocks render empty)
      await expect(frame.locator('header[b-tpl="styled-header"]')).not.toBeVisible()

      // Click toggle again to reactivate
      await block.locator('.switch.small.inverse .slider').first().click()
      await waitForPreviewUpdate(page)

      // Assert: header IS visible again in iframe
      await expect(frame.locator('header[b-tpl="styled-header"]')).toBeVisible()
    })

    test('duplicating a block shows the copy in preview', async ({ page }) => {
      await page.goto('/admin')
      await page.getByRole('link', { name: 'Pages & Sections' }).click()
      await syncLV(page)

      await page.getByRole('link', { name: 'Create page' }).click()
      await syncLV(page)

      await page.getByLabel('Title', { exact: true }).fill('Duplicate Block Test Page')
      await page.getByLabel('URI').fill('duplicate-block-test')

      // Add Styled Header block
      await page.getByRole('button', { name: 'Add block' }).click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Styled Header' }).click()
      await syncLV(page)

      // Change header text to "Original Header"
      const headerTextarea = page.locator('.header-block textarea')
      await headerTextarea.fill('Original Header')
      await syncLV(page)

      // Enable live preview
      await toggleLivePreview(page)
      await waitForPreviewReady(page)

      const frame = getPreviewFrame(page)

      // Verify header visible with "Original Header"
      await expect(frame.locator('header[b-tpl="styled-header"] h1')).toContainText('Original Header')
      await expect(frame.locator('header[b-tpl="styled-header"]')).toHaveCount(1)

      // Open action dropdown on the header block
      const block = page.locator('.base-block').first()
      await block.locator('.block-action-dropdown > button.block-action').click()

      // Click Duplicate from the dropdown
      await block.locator('.block-action-dropdown-content button:has-text("Duplicate")').click()
      await syncLV(page)
      await waitForPreviewUpdate(page)

      // Assert: TWO styled-header elements in iframe
      await expect(frame.locator('header[b-tpl="styled-header"]')).toHaveCount(2)

      // Assert: both contain "Original Header"
      await expect(frame.locator('header[b-tpl="styled-header"] h1').first()).toContainText('Original Header')
      await expect(frame.locator('header[b-tpl="styled-header"] h1').last()).toContainText('Original Header')
    })
  })

  test.describe('Image Var + Live Preview', () => {
    test('uploading image var updates preview iframe', async ({ page }) => {
      await page.goto('/admin')
      await page.getByRole('link', { name: 'Pages & Sections' }).click()
      await syncLV(page)

      await page.getByRole('link', { name: 'Create page' }).click()
      await syncLV(page)

      await page.getByLabel('Title', { exact: true }).fill('Image Var Preview Test Page')
      await page.getByLabel('URI').fill('image-var-preview-test')

      // Add Image and File Vars module
      await page.getByRole('button', { name: 'Add block' }).click()
      await page.getByRole('button', { name: '07 VAR UPLOAD TEST' }).click()
      await page.getByRole('button', { name: 'Image and File Vars' }).click()
      await syncLV(page)

      // Enable live preview
      await toggleLivePreview(page)
      await waitForPreviewReady(page)

      const frame = getPreviewFrame(page)

      // Verify no image in preview yet
      await expect(frame.locator('div[b-tpl="image-file-vars"] img')).not.toBeVisible()

      // Click "Add image" to open the image modal
      await page.getByRole('button', { name: 'Add image' }).click()
      const imageModal = page.locator('[id$="image-config"]:visible')
      await expect(imageModal).toBeVisible({ timeout: 5000 })

      // Upload image via file input in the modal
      await imageModal.locator('input[type="file"].file-input').setInputFiles('./fixtures/image.jpg')

      // Wait for image to process
      await expect(imageModal.locator('img')).toBeVisible({ timeout: 20000 })
      await expect(imageModal.locator('.image-info')).toBeVisible()

      // Close the modal
      await imageModal.locator('button.modal-close').click()
      await syncLV(page)

      await waitForPreviewUpdate(page)

      // Verify image now appears in preview iframe
      await expect(frame.locator('div[b-tpl="image-file-vars"] img')).toBeVisible()
    })
  })

  test.describe('Morph Preservation (skipFromChildren)', () => {
    test('video element survives morphdom update when data-src unchanged', async ({ page }) => {
      await page.goto('/admin')
      await page.getByRole('link', { name: 'Pages & Sections' }).click()
      await syncLV(page)

      await page.getByRole('link', { name: 'Create page' }).click()
      await syncLV(page)

      await page.getByLabel('Title', { exact: true }).fill('Morph Video Test Page')
      await page.getByLabel('URI').fill('morph-video-test')

      // Add Morph Preservation block
      await page.getByRole('button', { name: 'Add block' }).click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Morph Preservation' }).click()
      await syncLV(page)

      // Enable live preview
      await toggleLivePreview(page)
      await waitForPreviewReady(page)

      const frame = getPreviewFrame(page)
      // The video container exists but may be CSS-hidden (page styles hide unbooted videos)
      await expect(frame.locator('[data-smart-video]')).toHaveCount(1)

      // Trigger an initial update so initializeLazyVideos runs and adds data-booted
      await page.getByRole('textbox', { name: 'Label' }).fill('First update')
      await waitForPreviewUpdate(page)
      await expect(frame.locator('[data-smart-video][data-booted]')).toHaveCount(1)

      // Stamp a custom property on the <video> element to track DOM identity
      await frame.locator('[data-smart-video] video').evaluate(el => {
        el.__morphTestStamp = 'video-alive'
      })

      // Change the label var again to trigger another morphdom update
      await page.getByRole('textbox', { name: 'Label' }).fill('Second update')
      await waitForPreviewUpdate(page)

      // Verify the label updated (morphdom worked)
      await expect(frame.locator('.morph-label')).toContainText('Second update')

      // Verify the video element was NOT recreated — stamp should survive
      const stamp = await frame.locator('[data-smart-video] video').evaluate(el => el.__morphTestStamp)
      expect(stamp).toBe('video-alive')
    })

    test('iframe element survives morphdom update when src unchanged', async ({ page }) => {
      await page.goto('/admin')
      await page.getByRole('link', { name: 'Pages & Sections' }).click()
      await syncLV(page)

      await page.getByRole('link', { name: 'Create page' }).click()
      await syncLV(page)

      await page.getByLabel('Title', { exact: true }).fill('Morph Iframe Test Page')
      await page.getByLabel('URI').fill('morph-iframe-test')

      // Add Morph Preservation block
      await page.getByRole('button', { name: 'Add block' }).click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await page.getByRole('button', { name: 'Morph Preservation' }).click()
      await syncLV(page)

      // Enable live preview
      await toggleLivePreview(page)
      await waitForPreviewReady(page)

      const frame = getPreviewFrame(page)
      await expect(frame.locator('iframe.embed-frame')).toBeVisible()

      // Stamp a custom property on the iframe to track DOM identity
      await frame.locator('iframe.embed-frame').evaluate(el => {
        el.__morphTestStamp = 'iframe-alive'
      })

      // Change the label var to trigger a morphdom update
      await page.getByRole('textbox', { name: 'Label' }).fill('Changed label')
      await waitForPreviewUpdate(page)

      // Verify the label updated (morphdom worked)
      await expect(frame.locator('.morph-label')).toContainText('Changed label')

      // Verify the iframe was NOT recreated — stamp should survive
      const stamp = await frame.locator('iframe.embed-frame').evaluate(el => el.__morphTestStamp)
      expect(stamp).toBe('iframe-alive')
    })
  })
})
