import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('seo changes affect the frontpage', async ({ page }) => {
  await page.goto('/admin')
  await page.getByText('Configuration').click()
  await page.getByRole('link', { name: 'SEO' }).click()
  await expect(page).toHaveURL('/admin/config/seo')
  await syncLV(page)
  await page.getByLabel('Fallback META title').fill('Brando CMS')
  await page
    .getByLabel('Fallback META description')
    .fill('Brando CMS: A CMS of sorts.')
  await page.getByPlaceholder('https://yoursite.com').fill('https://brando.dev')
  await page.locator('textarea[name="seo[robots]"]').fill('noindex, nofollow')
  await page.getByRole('button', { name: 'Add entry' }).click()
  await page.locator('input[name="seo[redirects][0][code]"]').click()
  await page.locator('input[name="seo[redirects][0][code]"]').fill('301')
  // Add SEO image
  // await page.getByRole('button', { name: 'Add image' }).click()
  // await page
  //   .locator('input[name="fallback_meta_image"]')
  //   .setInputFiles('./fixtures/image.jpg')
  // await page.getByRole('button', { name: 'Close' }).click()
  // await expect(page.getByText('No image associated with')).toHaveCount(0)
  // await page.waitForSelector('.image-wrapper-compact > .img-placeholder', {
  //   state: 'detached',
  // })
  await page.getByTestId('submit').click()
  await syncLV(page)
  await expect(page).toHaveURL('/admin/config/seo')

  await page.goto('/')
  const metaDescriptionLocator = page.locator('meta[name="description"]')
  const metaDescription = await metaDescriptionLocator.getAttribute('content')
  expect(metaDescription).toBe('Brando CMS: A CMS of sorts.')

  const metaTitleLocator = page.locator('meta[name="title"]')
  const metaTitle = await metaTitleLocator.getAttribute('content')
  expect(metaTitle).toBe('Index')
})

// test('reorder menu items', async ({ page }) => {
//   await page.goto('/admin')
//   await page.getByText('Configuration').click()
//   await page.getByRole('link', { name: 'Navigation' }).click()
//   await expect(page).toHaveURL('/admin/config/navigation/menus')
//   await page.getByRole('link', { name: 'Main menu →' }).click()
//   await expect(page).toHaveURL('/admin/config/navigation/menus/update/1')

//   await page.locator('.subform-handle').first().hover()
//   await page.mouse.down()
//   await page
//     .locator('div:nth-child(9) > .subform-tools > .subform-handle')
//     .hover()
//   await page
//     .locator('div:nth-child(9) > .subform-tools > .subform-handle')
//     .hover()
//   await page.waitForTimeout(300)
//   await page.mouse.up()

//   await syncLV(page)
//   await page.getByTestId('submit').click()
//   await syncLV(page)
//   await expect(page).toHaveURL('/admin/config/navigation/menus')

//   await page.goto('/')

//   // Wait for the menu items to be loaded
//   await page.waitForSelector('[data-menu-item-key]')

//   // Get all elements with data-menu-item-key in DOM order
//   const menuItemKeys = await page.$$eval('[data-menu-item-key]', (elements) =>
//     elements.map((el) => el.getAttribute('data-menu-item-key'))
//   )

//   // Check that both keys are present
//   expect(menuItemKeys).toContain('brando')
//   expect(menuItemKeys).toContain('guides')

//   // Find the indices of 'brando' and 'guides'
//   const brandoIndex = menuItemKeys.indexOf('brando')
//   const guidesIndex = menuItemKeys.indexOf('guides')

//   // Assert that 'brando' comes after 'guides'
//   expect(brandoIndex).toBeGreaterThan(guidesIndex)
// })
