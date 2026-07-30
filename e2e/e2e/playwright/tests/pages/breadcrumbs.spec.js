import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test('pages have JSON-LD breadcrumbs', async ({ page }) => {
  // Create a parent page "Services" via admin
  await page.goto('/admin')
  await page.getByRole('link', { name: 'Pages & Sections' }).click()
  await page.getByRole('link', { name: 'Create page' }).click()
  await syncLV(page)

  await page.locator('label').filter({ hasText: 'Published' }).click()
  await page.getByLabel('Title', { exact: true }).fill('Services')
  await page.getByLabel('URI').fill('services')

  await page.getByRole('button', { name: 'Add block' }).click()
  await page.getByRole('button', { name: 'HEADERS' }).click()
  await page.getByRole('button', { name: 'Heading', exact: true }).click()
  await expect(page.locator('#block-field-blocks-module-picker')).not.toBeVisible()
  await page.getByText('Text', { exact: true }).click()
  await page.getByText('Text', { exact: true }).fill('Our Services')

  await syncLV(page)
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/pages')
  await syncLV(page)
  await expect(page.getByRole('link', { name: 'Services →' })).toBeVisible()

  // Create a child page "Design" with "Services" as parent
  await page.getByRole('link', { name: 'Create page' }).click()
  await syncLV(page)

  await page.locator('label').filter({ hasText: 'Published' }).click()
  await page.getByLabel('Title', { exact: true }).fill('Design')
  await page.getByLabel('URI').fill('services/design')

  // Set parent page to "Services" using the custom select modal
  const parentWrapper = page.locator('.field-wrapper', { has: page.locator('input[name="page[parent_id]"]') })
  await parentWrapper.locator('button.button-edit').click()
  const selectModal = page.locator('#select-page_parent_id-modal')
  await expect(selectModal).toBeVisible()
  await selectModal.getByText('Services', { exact: true }).click()
  await selectModal.getByRole('button', { name: 'OK' }).click()
  await syncLV(page)

  await page.getByRole('button', { name: 'Add block' }).click()
  await page.getByRole('button', { name: 'HEADERS' }).click()
  await page.getByRole('button', { name: 'Heading', exact: true }).click()
  await expect(page.locator('#block-field-blocks-module-picker')).not.toBeVisible()
  await page.getByText('Text', { exact: true }).click()
  await page.getByText('Text', { exact: true }).fill('Design Services')

  await syncLV(page)
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/pages')
  await syncLV(page)

  const servicesRow = page.locator('.list-row', { has: page.getByRole('link', { name: 'Services →' }) })
  const childrenButton = servicesRow.getByTestId('children-button')
  await expect(childrenButton).toHaveAccessibleName('+ 1')
  await childrenButton.click()
  await expect(childrenButton).toHaveAccessibleName('Close')
  await expect(servicesRow.locator('.child-row').getByText('Design', { exact: true })).toBeVisible()
  await childrenButton.click()
  await expect(servicesRow.locator('.child-row')).toHaveCount(0)

  // Visit the parent page and verify JSON-LD breadcrumbs
  await page.goto('/services')
  await expect(page.getByRole('heading', { name: 'Our Services' })).toBeVisible()

  // Extract and parse the JSON-LD script tag
  let jsonLd = await page.evaluate(() => {
    const script = document.querySelector('script[type="application/ld+json"]')
    return script ? JSON.parse(script.textContent) : null
  })

  expect(jsonLd).not.toBeNull()
  expect(jsonLd['@graph']).toBeDefined()

  let breadcrumbEntity = jsonLd['@graph'].find(e => e['@type'] === 'BreadcrumbList')
  expect(breadcrumbEntity).toBeDefined()
  expect(breadcrumbEntity.itemListElement).toHaveLength(2)
  expect(breadcrumbEntity.itemListElement[0].name).toBe('E2eProject')
  expect(breadcrumbEntity.itemListElement[0].position).toBe(1)
  expect(breadcrumbEntity.itemListElement[1].name).toBe('Services')
  expect(breadcrumbEntity.itemListElement[1].position).toBe(2)

  // Visit the child page and verify nested breadcrumbs
  await page.goto('/services/design')
  await expect(page.getByRole('heading', { name: 'Design Services' })).toBeVisible()

  jsonLd = await page.evaluate(() => {
    const script = document.querySelector('script[type="application/ld+json"]')
    return script ? JSON.parse(script.textContent) : null
  })

  expect(jsonLd).not.toBeNull()
  expect(jsonLd['@graph']).toBeDefined()

  breadcrumbEntity = jsonLd['@graph'].find(e => e['@type'] === 'BreadcrumbList')
  expect(breadcrumbEntity).toBeDefined()
  expect(breadcrumbEntity.itemListElement).toHaveLength(3)
  expect(breadcrumbEntity.itemListElement[0].name).toBe('E2eProject')
  expect(breadcrumbEntity.itemListElement[0].position).toBe(1)
  expect(breadcrumbEntity.itemListElement[1].name).toBe('Services')
  expect(breadcrumbEntity.itemListElement[1].position).toBe(2)
  expect(breadcrumbEntity.itemListElement[2].name).toBe('Design')
  expect(breadcrumbEntity.itemListElement[2].position).toBe(3)

  // Verify the WebPage entity references the breadcrumbs
  const webPageEntity = jsonLd['@graph'].find(e =>
    e['@type'] === 'WebPage' || e['@type'] === 'AboutPage'
  )
  expect(webPageEntity).toBeDefined()
  expect(webPageEntity.breadcrumb).toBeDefined()
  expect(webPageEntity.breadcrumb['@id']).toContain('#breadcrumb')
})
