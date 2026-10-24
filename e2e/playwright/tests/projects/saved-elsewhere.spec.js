import { test, expect } from '../../test-support/setupAuth'
import { syncLV, setEntryStatus } from '../../utils'

// One project open by two editors. A picks categories (a has_many
// multi-select, which doesn't ship as a field edit) and publishes, which
// makes the save set `publish_at`. B takes what A saved; before, it kept the
// form it opened with, and its own save deleted the categories and blanked
// the publishing date. One editor's two tabs don't both edit (one tab per
// user, `forms/one-tab-per-user.spec.js`): the tab that takes over has the
// categories the other picked.

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', {
    data: { schema, attributes, creator_id: 1, fields: ['id'] },
  })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

const categories = page => page.locator('#project_project_categories-selected-options .selected-label')
const publishAt = page => page.locator('input[name="project[publish_at]"]')

async function saveAndContinue(page) {
  await page.getByTestId('split-dropdown-button').click()
  await page.getByRole('button', { name: /Save and continue editing/ }).click()
  await expect(page.locator('.toast-stack')).toContainText(/updated/i)
}

test('an editor takes the categories and publishing date another editor saved, and their own save keeps them', async ({
  page,
  secondUserPage,
}) => {
  const client = await factory(page, 'E2eProject.Projects.Client', {
    name: 'Saved elsewhere client',
    slug: 'saved-elsewhere-client',
    status: 'published',
    language: 'en',
  })

  for (const title of ['Category North', 'Category South']) {
    await factory(page, 'E2eProject.Projects.Category', {
      title,
      slug: title.toLowerCase().replace(' ', '-'),
      status: 'published',
      language: 'en',
    })
  }

  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: 'Saved elsewhere',
    slug: 'saved-elsewhere',
    client_id: client.id,
    introduction: '<p>Opened in two tabs.</p>',
    status: 'draft',
    language: 'en',
  })

  const url = `/admin/projects/projects/update/${project.id}`
  const tab2 = secondUserPage
  await tab2.goto(url)
  await syncLV(tab2)
  await expect(categories(tab2)).toHaveCount(0)
  await expect(publishAt(tab2)).toHaveValue('')

  await page.goto(url)
  await syncLV(page)

  // Tab 1 picks two categories, publishes and saves
  await page.locator('#project_project_categories-field-base').getByRole('button', { name: 'Select' }).click()
  await page.getByRole('checkbox', { name: 'Category North' }).click()
  await syncLV(page)
  await page.getByRole('checkbox', { name: 'Category South' }).click()
  await syncLV(page)
  await page.getByRole('button', { name: 'OK' }).click()
  await syncLV(page)
  await expect(categories(page)).toHaveCount(2)

  await setEntryStatus(page, 'published')
  await syncLV(page)
  await saveAndContinue(page)
  await syncLV(page)
  await expect(publishAt(page)).not.toHaveValue('')
  const saved = await publishAt(page).inputValue()

  // Tab 2 shows both categories, and its form holds the saved date
  await expect(categories(tab2)).toHaveCount(2)
  await expect(categories(tab2).filter({ hasText: 'Category North' })).toHaveCount(1)
  await expect(categories(tab2).filter({ hasText: 'Category South' })).toHaveCount(1)
  await expect(publishAt(tab2)).toHaveValue(saved)
  await expect(tab2.getByTestId('status-trigger')).toHaveAttribute('data-status', 'published')

  // Tab 2's save keeps them
  await syncLV(tab2)
  await saveAndContinue(tab2)
  await tab2.reload()
  await syncLV(tab2)
  await expect(categories(tab2)).toHaveCount(2)
  await expect(publishAt(tab2)).toHaveValue(saved)
  await expect(tab2.getByTestId('status-trigger')).toHaveAttribute('data-status', 'published')
})

// The categories one tab picked and didn't save are in the tab that takes
// over editing from it.
test('a tab that takes over has the categories the other tab picked', async ({ page }) => {
  const client = await factory(page, 'E2eProject.Projects.Client', {
    name: 'Conflict client',
    slug: 'conflict-client',
    status: 'published',
    language: 'en',
  })

  for (const title of ['Category East', 'Category West']) {
    await factory(page, 'E2eProject.Projects.Category', {
      title,
      slug: title.toLowerCase().replace(' ', '-'),
      status: 'published',
      language: 'en',
    })
  }

  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: 'Changed in two tabs',
    slug: 'changed-in-two-tabs',
    client_id: client.id,
    introduction: '<p>Opened in two tabs.</p>',
    status: 'draft',
    language: 'en',
  })

  const url = `/admin/projects/projects/update/${project.id}`
  await page.goto(url)
  await syncLV(page)
  const tab2 = await page.context().newPage()
  await tab2.goto(url)
  await syncLV(tab2)
  await expect(tab2.getByTestId('tab-notice')).toBeVisible()

  await page.locator('#project_project_categories-field-base').getByRole('button', { name: 'Select' }).click()
  await page.getByRole('checkbox', { name: 'Category West' }).click()
  await syncLV(page)
  await page.getByRole('button', { name: 'OK' }).click()
  await syncLV(page)
  await expect(categories(page)).toHaveText(['Category West'])
  await expect(categories(tab2)).toHaveText(['Category West'])

  await tab2.getByTestId('tab-notice').getByRole('button', { name: 'Edit here' }).click()
  await expect(tab2.getByTestId('tab-notice')).toBeHidden()
  await expect(categories(tab2)).toHaveText(['Category West'])

  await saveAndContinue(tab2)
  await tab2.reload()
  await syncLV(tab2)
  await expect(categories(tab2)).toHaveText(['Category West'])

  await tab2.close()
})
