import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// The image picker for one field lists the images made for that field's image
// config. The rest of the library is offered too: Root (or "Whole library")
// leads there, and an image made for another config is copied into the
// field's config when it is picked, so the field renders sizes it has.

test.beforeEach(async ({ page }) => {
  expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
})

test('a meta image can be picked from the whole library and is cut to the field', async ({ page }) => {
  // An image in the library made for the default config, its file on disk
  const response = await page.request.post('/e2e/alt-text-image')
  expect(response.ok()).toBe(true)
  const { id: libraryImageId } = await response.json()

  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/pages/update/1')
  await syncLV(page)

  await page.locator('.form-tool-meta').click()
  const imageField = page.locator('#page_meta_image-media')
  await imageField.getByRole('button', { name: 'Velg bilde', exact: true }).click()

  const picker = page.getByRole('dialog', { name: 'Bilder', exact: true })
  await expect(picker).toBeVisible()
  const scope = picker.locator('.image-picker-scope')
  await expect(scope.getByRole('button', { name: 'Satt opp for dette feltet' })).toHaveAttribute('aria-pressed', 'true')
  await expect(picker.locator('.image-picker__image')).toHaveCount(0)

  // Root at the field's own folder goes on to the library's root
  await picker.getByRole('button', { name: 'Rot', exact: true }).click()
  await expect(scope.getByRole('button', { name: 'Hele biblioteket' })).toHaveAttribute('aria-pressed', 'true')
  const libraryRow = picker.locator(`.image-picker__image[data-id="${libraryImageId}"]`)
  await expect(libraryRow).toBeVisible()

  await libraryRow.click()
  await expect(picker).not.toBeVisible()
  await syncLV(page)

  // The field holds a copy in its own upload path, not the picked image
  const picked = imageField.locator('input[type="hidden"][name="page[meta_image_id]"]')
  await expect(picked).not.toHaveValue('')
  await expect(picked).not.toHaveValue(String(libraryImageId))
  await expect(imageField.locator('img')).toHaveAttribute('src', /\/images\/meta\//, { timeout: 30000 })

  // and the copy is one of the field's own images now
  await imageField.getByRole('button', { name: 'Velg bilde', exact: true }).click()
  await expect(picker).toBeVisible()
  await expect(scope.getByRole('button', { name: 'Satt opp for dette feltet' })).toHaveAttribute('aria-pressed', 'true')
  const copyId = await picked.inputValue()
  await expect(picker.locator(`.image-picker__image[data-id="${copyId}"]`)).toBeVisible()
  await picker.getByRole('button', { name: 'Lukk', exact: true }).click()
  await expect(picker).not.toBeVisible()

  // The image drawer's "Velg bilde" opens the picker for the field too, and
  // the library is offered there; picking the same file again gives the
  // same copy
  await imageField.getByRole('button', { name: 'Konfigurer', exact: true }).click()
  const imageDrawer = page.locator('#image-drawer')
  await imageDrawer.getByRole('button', { name: 'Erstatt', exact: true }).click()
  await imageDrawer.getByRole('button', { name: 'Velg bilde', exact: true }).click()
  await expect(picker).toBeVisible()
  await scope.getByRole('button', { name: 'Hele biblioteket' }).click()
  await expect(scope.getByRole('button', { name: 'Hele biblioteket' })).toHaveAttribute('aria-pressed', 'true')
  await picker.locator(`.image-picker__image[data-id="${libraryImageId}"]`).click()
  await expect(picker).not.toBeVisible()
  await syncLV(page)
  await expect(picked).toHaveValue(copyId)
  await imageDrawer.getByRole('button', { name: 'Lukk', exact: true }).first().click()
  await syncLV(page)

  await page.locator('[id$="-meta-drawer"]').getByRole('button', { name: 'Lukk', exact: true }).click()
  await syncLV(page)
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/pages')

  // The page is shared with the copy, cut to the meta image's sizes
  await page.goto('/')
  await expect(page.locator('meta[property="og:image"]')).toHaveAttribute('content', /\/images\/meta\//)
})
