import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('creates a simple page', async ({ page }) => {
  await page.goto('/admin')
  await page.getByRole('link', { name: 'Pages & Sections' }).click()
  await page.getByRole('link', { name: 'Create page' }).click()
  await syncLV(page)

  await page.locator('label').filter({ hasText: 'Published' }).click()
  await page.getByLabel('Title', { exact: true }).click()
  await page.getByLabel('Title', { exact: true }).fill('About')
  await page.getByLabel('URI').click()
  await page.getByLabel('URI').fill('about')

  // add heading block
  await page.getByRole('button', { name: 'Add block' }).click()
  await page.getByRole('button', { name: 'HEADERS' }).click()
  await page.getByRole('button', { name: 'Heading Large text' }).click()
  await expect(page.locator('#block-field-blocks-module-picker')).not.toBeVisible()
  await expect(page.getByText('Module | Heading')).toBeVisible()
  await page.getByText('Text').click()
  await page.getByText('Text').fill('About Brando CMS')

  // add media block
  await page.getByRole('button', { name: 'Add block' }).nth(1).click()
  await page.getByRole('button', { name: 'MEDIA' }).click()
  await page.getByRole('button', { name: 'Single Asset Full width image' }).click()
  await expect(page.locator('#block-field-blocks-module-picker')).not.toBeVisible()
  await expect(page.getByText('Module | Single asset')).toBeVisible()

  // ensure that we can edit the module's var and interact with it afterwards
  await page.getByRole('textbox', { name: 'String label' }).click()
  await page.getByRole('textbox', { name: 'String label' }).fill('New Value')

  await syncLV(page)

  await page.getByRole('button', { name: 'Video' }).click()

  // we can wait until we have [data-block-type="video"] in the DOM
  await page.waitForSelector('[data-block-type="video"]', { state: 'visible' })
  await page.getByRole('button', { name: 'Select or create video' }).click()

  // Wait for the video picker drawer to be visible
  const videoPicker = page.locator('#video-picker')
  await expect(videoPicker).toBeVisible()

  // Click to show URL input section
  await videoPicker.getByRole('button', { name: 'Create new video from URL' }).click()

  // Fill the video URL
  const videoUrlInput = videoPicker.locator('input.text').first()
  await videoUrlInput.fill('https://vimeo.com/347119375')

  await syncLV(page)

  // Click Create video button
  await videoPicker.getByRole('button', { name: 'Create video' }).click()

  // Wait for "Analyzing video..." to appear and then disappear
  await expect(videoPicker.getByText('Analyzing video...')).toBeVisible({ timeout: 10000 })
  await expect(videoPicker.getByText('Analyzing video...')).not.toBeVisible({ timeout: 30000 })

  // Close the drawer
  await videoPicker.getByRole('button', { name: 'Close' }).click()
  await page.waitForSelector('#video-picker', { state: 'hidden' })

  // Verify video was added (video block should now show video content)
  await expect(page.locator('[data-block-type="video"]')).toBeVisible()

  // add text block
  await page.getByRole('button', { name: 'Add block' }).nth(2).click()
  await page.getByRole('button', { name: 'general' }).click()
  await page.getByRole('button', { name: 'Example module Used for the' }).click()
  await expect(page.locator('#block-field-blocks-module-picker')).not.toBeVisible()
  await expect(page.getByText('Module | Example module')).toBeVisible()
  const exampleBlock = page.locator('.entry-block').nth(2)
  await exampleBlock.locator('textarea').filter({ hasText: 'Heading' }).fill('Another heading')

  const editor = exampleBlock.locator('.tiptap-wrapper [contenteditable="true"]')
  await editor.click()
  await page.keyboard.down('ControlOrMeta')
  await page.keyboard.press('A')
  await page.keyboard.up('ControlOrMeta')
  await page.keyboard.press('Backspace')

  // Type new content
  await page.keyboard.type('Hello from Playwright!')

  const editorContent = await editor.innerText()
  expect(editorContent).toBe('Hello from Playwright!')

  // Blur the editor to trigger TipTap sync with hidden input
  await page.waitForTimeout(100)
  await editor.evaluate(el => el.blur())
  await page.waitForTimeout(200)

  await syncLV(page)
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/pages')
  await syncLV(page)
  await expect(page.getByRole('link', { name: 'About →' })).toBeVisible()
  await expect(page.getByRole('link', { name: '/about' })).toBeVisible()

  // take a look at the frontend
  await page.goto('/about')
  await expect(page.getByRole('heading', { name: 'About Brando CMS' })).toBeVisible()

  await expect(page.getByRole('heading', { name: 'Another heading' })).toBeVisible()

  await expect(page.getByText('Hello from Playwright!')).toBeVisible()
})

test('duplicates to other language', async ({ page }) => {
  await page.goto('/admin')
  await page.getByRole('link', { name: 'Pages & Sections' }).click()
  await page.getByRole('link', { name: 'Create page' }).click()
  await syncLV(page)
  await page.getByText('Published', { exact: true }).click()
  await page.getByLabel('Title', { exact: true }).fill('Clients')
  await page.getByLabel('URI').fill('clients')
  await page.getByRole('button', { name: 'Add block' }).click()
  await page.getByRole('button', { name: 'HEADERS' }).click()
  await page.getByRole('button', { name: 'Heading Large text' }).click()
  await page.locator('textarea').filter({ hasText: 'Text' }).first().fill('Heading')
  await page.getByTestId('submit').click()
  await expect(page.getByRole('link', { name: 'Clients →' })).toBeVisible()
  await expect(page.getByRole('link', { name: '/clients' })).toBeVisible()
  await page.locator('.list-row').nth(1).getByTestId('circle-dropdown-button').click()
  await page.getByRole('button', { name: 'Duplicate to [NO]' }).click()
  await expect(page.getByLabel('Title', { exact: true })).toBeVisible()
  await expect(page.getByText('/no/clients')).toBeVisible()
})

test('creates meta information', async ({ page }) => {
  await page.goto('/admin')
  await page.getByRole('link', { name: 'Pages & Sections' }).click()
  await page.getByRole('link', { name: 'Create page' }).click()
  await syncLV(page)

  await page.getByLabel('Published').check()
  await page.getByLabel('Title', { exact: true }).click()
  await page.getByLabel('Title', { exact: true }).fill('Hello')
  await page.getByLabel('URI').click()
  await page.getByLabel('URI').fill('hello')

  // add heading block
  await page.getByRole('button', { name: 'Add block' }).click()
  await page.getByRole('button', { name: 'HEADERS' }).click()
  await page.getByRole('button', { name: 'Heading Large text' }).click()
  await expect(page.locator('#block-field-blocks-module-picker')).not.toBeVisible()
  await expect(page.getByText('Module | Heading')).toBeVisible()
  await page.getByText('Text').click()
  await page.getByText('Text').fill('Hello!')

  // open meta drawer
  await page.getByRole('button', { name: 'Meta' }).click()
  await page.locator('input[name="page[meta_title]"]').fill('Overridden title')
  await page.locator('textarea[name="page[meta_description]"]').fill('Overridden description')

  // Add SEO image
  await page.getByRole('button', { name: 'Add image' }).click()
  await page.locator('input[name="meta_image"]').setInputFiles('./fixtures/image.jpg')
  // Wait for upload to complete - the image should appear in the drawer
  await expect(page.locator('#image-drawer img')).toBeVisible({ timeout: 30000 })
  // Close drawer - this should save the image selection
  await page.getByRole('button', { name: 'Close' }).first().click()
  await page.waitForSelector('#image-drawer', { state: 'hidden' })
  await syncLV(page)
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/pages')
  await syncLV(page)

  // take a look at the frontend
  await page.goto('/hello')
  await expect(page.getByRole('heading', { name: 'Hello!' })).toBeVisible()

  const metaDescriptionLocator = page.locator('meta[name="description"]')
  const metaDescription = await metaDescriptionLocator.getAttribute('content')
  expect(metaDescription).toBe('Overridden description')

  const metaTitleLocator = page.locator('meta[name="title"]')
  const metaTitle = await metaTitleLocator.getAttribute('content')
  expect(metaTitle).toBe('Overridden title')
})
