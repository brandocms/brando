import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// save_file must ship field changes to other connected editors exactly like
// save_image/save_video do. Regression: file drawer saves skipped
// ship_all_field_changes — a second editor never saw the file until reload,
// and their subsequent save could clobber it.
test('file drawer save ships the file field to a second connected editor', async ({
  page,
  secondUserPage,
}) => {
  test.setTimeout(120000)

  // A opens a seeded project (untouched by other specs)
  await page.goto('/admin/projects/projects')
  await syncLV(page)
  await page.getByRole('link', { name: 'Test Project Gamma' }).click()
  await syncLV(page)
  await expect(page.getByRole('button', { name: 'Add file' })).toBeVisible({ timeout: 10000 })

  // B opens the same entry
  const path = new URL(page.url()).pathname
  await secondUserPage.goto(path)
  await syncLV(secondUserPage)
  await expect(secondUserPage.getByRole('button', { name: 'Add file' })).toBeVisible({
    timeout: 10000,
  })

  // A uploads a file and saves it via the drawer (closing dispatches submit →
  // save_file → ship_all_field_changes)
  await page.getByRole('button', { name: 'Add file' }).click()
  await syncLV(page)
  await page.locator('#file-drawer-upload-input').setInputFiles('./fixtures/test.pdf')
  // the drawer renders .file-info once the uploaded file is delivered
  await expect(page.locator('#file-drawer .file-info')).toBeVisible({ timeout: 20000 })
  await syncLV(page)
  await page.locator('#file-drawer').getByRole('button', { name: 'Close' }).click()
  await page.waitForSelector('#file-drawer', { state: 'hidden' })
  await syncLV(page)
  await expect(page.getByRole('button', { name: 'Edit file' })).toBeVisible({ timeout: 20000 })

  // B must see the file WITHOUT reloading — the shipped field change applies
  // to B's form in place
  await expect(secondUserPage.getByRole('button', { name: 'Edit file' })).toBeVisible({
    timeout: 15000,
  })
})
