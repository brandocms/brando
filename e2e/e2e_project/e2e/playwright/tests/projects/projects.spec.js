import { test, expect } from '../../test-support/setupAuth'
import { syncLV, dragAndDrop } from '../../utils'

test('creates project', async ({ page }) => {
  await page.goto('/admin')
  await page.getByRole('link', { name: 'Clients' }).click()
  await page.getByRole('link', { name: 'Create new' }).click()
  await syncLV(page)
  await page.getByText('Published').click()
  await page.getByRole('textbox', { name: 'Name' }).click()
  await page.getByRole('textbox', { name: 'Name' }).fill('Microsoft')
  await page.getByTestId('submit').click()
  await syncLV(page)
  await page.getByRole('link', { name: 'Categories' }).click()
  await page.getByRole('link', { name: 'Create new' }).click()
  await syncLV(page)
  await page.getByRole('textbox', { name: 'Title' }).click()
  await page.getByRole('textbox', { name: 'Title' }).fill('Design')
  await page.getByTestId('submit').click()
  await syncLV(page)
  await page.getByRole('link', { name: 'Create new' }).click()
  await page.getByRole('textbox', { name: 'Title' }).click()
  await page.getByRole('textbox', { name: 'Title' }).fill('Strategy')
  await page.getByTestId('submit').click()
  await syncLV(page)
  await page.getByRole('link', { name: 'Projects' }).click()
  await page.getByRole('link', { name: 'Create new' }).click()
  await syncLV(page)

  await page.locator('label').filter({ hasText: 'Published' }).click()
  await page.getByRole('textbox', { name: 'Title' }).click()
  await page.getByRole('textbox', { name: 'Title' }).fill('Microsoft')
  await page.getByText('Published', { exact: true }).click()
  await page.locator('#project_full_case-field-base div').click()

  const editor = page.locator('.tiptap-wrapper [contenteditable="true"]')

  await expect(editor).toBeVisible()
  await expect(editor).toBeEnabled()
  await editor.click() // Focus the editor
  await editor.fill('Hello from Playwright!')
  const editorContent = await editor.innerText()
  expect(editorContent).toBe('Hello from Playwright!')

  // check the input value of `input[name="project[introduction]"]`
  const introductionInput = page.locator('input[name="project[introduction]"]')
  const introductionInputValue = await introductionInput.inputValue()
  expect(introductionInputValue).toBe('<p>Hello from Playwright!</p>')

  await introductionInput.dispatchEvent('input', { bubbles: true })
  await introductionInput.dispatchEvent('change', { bubbles: true })

  await syncLV(page)
  await page.waitForTimeout(1000)

  await page
    .locator('#project_project_categories-field-base')
    .getByRole('button', { name: 'Select' })
    .click()
  await page.getByRole('button', { name: 'Design' }).click()
  await page.getByRole('button', { name: 'Strategy' }).click()
  await page.getByRole('button', { name: 'OK' }).click()
  await page
    .locator('#project_client_id-field-base')
    .getByRole('button', { name: 'Select' })
    .click()
  await page.getByRole('button', { name: 'Microsoft' }).click()

  // Add image
  await page.getByRole('button', { name: 'Add image' }).click()
  await page.locator('input[name="listing_image"]').setInputFiles('./fixtures/image.jpg')
  // Close drawer
  await page.getByRole('button', { name: 'Close' }).first().click()
  // Wait for the drawer to vanish or the form to be detached
  await page.waitForSelector('#image-drawer', { state: 'hidden' })
  await page.evaluate(() => {
    document
      .querySelector('#image-drawer-form')
      .dispatchEvent(new Event('submit', { bubbles: true, cancelable: true }))
  })

  await syncLV(page)

  await page.locator('input[name="project_gallery"]').click()
  await page
    .locator('input[name="project_gallery"]')
    .setInputFiles(['./fixtures/image2.jpg', './fixtures/image.jpg'])

  await expect(page.locator('progress')).toHaveCount(0)

  const firstGalleryObjectImg = page
    .locator('#sortable-gallery-objects .gallery-object img')
    .first()
  const firstGalleryObjectImgSrc = await firstGalleryObjectImg.getAttribute('src')
  const filename = firstGalleryObjectImgSrc.split('/').pop()
  expect(filename.slice(0, 7)).toBe('image2-')

  const secondGalleryObjectImg = page
    .locator('#sortable-gallery-objects .gallery-object img')
    .nth(1)
  const secondGalleryObjectImgSrc = await secondGalleryObjectImg.getAttribute('src')
  const filename2 = secondGalleryObjectImgSrc.split('/').pop()
  expect(filename2.slice(0, 6)).toBe('image-')

  const firstGalleryObjectHandle = page
    .locator('#sortable-gallery-objects .gallery-object')
    .first()

  const secondGalleryObjectHandle = page
    .locator('#sortable-gallery-objects .gallery-object')
    .nth(1)

  // await firstGalleryObjectHandle.hover()
  // await page.mouse.down()
  // await secondGalleryObjectHandle.hover()
  // await page.waitForTimeout(300)
  // await page.mouse.up()

  const boundingBox = await firstGalleryObjectHandle.boundingBox()
  await dragAndDrop(page, firstGalleryObjectHandle, firstGalleryObjectHandle, {
    x: boundingBox.x + 250,
    y: boundingBox.y + 50,
  })

  await page.waitForTimeout(500)
  await syncLV(page)

  await page.getByRole('button', { name: 'Add block' }).click()
  await page.getByRole('button', { name: 'HEADERS' }).click()
  await page.getByRole('button', { name: 'Heading Large text' }).click()

  await syncLV(page)

  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/projects/projects')
  await expect(page.locator('.content-list .list-row').nth(0)).toContainText('Microsoft')
})
