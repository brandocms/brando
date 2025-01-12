import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('creates a simple page', async ({ page }) => {
  await page.goto('/admin')
  await page.getByRole('link', { name: 'Pages & Sections' }).click()
  await page.getByRole('link', { name: 'Create page' }).click()
  await syncLV(page)

  await page.getByLabel('Published').check()
  await page.getByLabel('Title', { exact: true }).click()
  await page.getByLabel('Title', { exact: true }).fill('About')
  await page.getByLabel('URI').click()
  await page.getByLabel('URI').fill('about')

  // add heading block
  await page.getByRole('button', { name: 'Add block' }).click()
  await page.getByRole('button', { name: 'HEADERS' }).click()
  await page.getByRole('button', { name: 'Heading Large text' }).click()
  await expect(
    page.locator('#block-field-blocks-module-picker')
  ).not.toBeVisible()
  await expect(page.getByText('Module | Heading')).toBeVisible()
  await page.getByText('Text').click()
  await page.getByText('Text').fill('About Brando CMS')

  // add media block
  await page.getByRole('button', { name: 'Add block' }).nth(1).click()
  await page.getByRole('button', { name: 'MEDIA' }).click()
  await page
    .getByRole('button', { name: 'Single Asset Full width image' })
    .click()
  await expect(
    page.locator('#block-field-blocks-module-picker')
  ).not.toBeVisible()
  await expect(page.getByText('Module | Single asset')).toBeVisible()
  await page.getByRole('button', { name: 'Video' }).click()
  await page.getByRole('button', { name: 'Configure video block' }).click()

  const videoBlock = page.locator('.entry-block').nth(1)
  const videoBlockModal = videoBlock.locator('.modal-dialog').nth(1)
  await expect(videoBlock).toBeVisible()
  await expect(videoBlockModal).toBeVisible()

  const videoUrlInput = videoBlockModal.locator('input.text').first()
  await videoUrlInput.fill(
    'https://player.vimeo.com/progressive_redirect/playback/1032335230/rendition/720p/file.mp4?loc=external&signature=034b7cc0c3c660623730fa713f59613c1cd9f268c43772f95205590f6bb7c114'
  )

  await syncLV(page)

  await videoBlockModal.getByRole('button', { name: 'Get video info' }).click()
  await expect(
    videoBlockModal.getByText('Fetching video information')
  ).toBeVisible()
  await expect(
    videoBlockModal.getByRole('button', { name: 'Select cover image' })
  ).toBeVisible({ timeout: 30000 })
  await videoBlockModal.getByRole('button', { name: 'Close' }).click()
  await expect(videoBlockModal).not.toBeVisible()

  // add text block
  await page.getByRole('button', { name: 'Add block' }).nth(2).click()
  await page.getByRole('button', { name: 'general' }).click()
  await page
    .getByRole('button', { name: 'Example module Used for the' })
    .click()
  await expect(
    page.locator('#block-field-blocks-module-picker')
  ).not.toBeVisible()
  await expect(page.getByText('Module | Example module')).toBeVisible()
  const exampleBlock = page.locator('.entry-block').nth(2)
  await exampleBlock.getByText('Text').click()
  await exampleBlock.getByText('Text').fill('More text')

  await exampleBlock.getByLabel('Rich-Text Editor').getByText('Text').click()
  await page.keyboard.type(
    'Lorem ipsum dolor sit amet, consectetur adipiscing elit.'
  )

  await syncLV(page)
  await page.getByTestId('submit').click()
  await syncLV(page)

  await expect(page).toHaveURL('/admin/pages')
  await expect(page.getByRole('link', { name: 'About →' })).toBeVisible()
  await expect(page.getByRole('link', { name: '/about' })).toBeVisible()

  // take a look at the frontend
  await page.goto('/about')
  await expect(
    page.getByRole('heading', { name: 'About Brando CMS' })
  ).toBeVisible()
})
