import { test, expect } from '../../test-support/setupAuth'
import { syncLV, setEntryStatus } from '../../utils'

// One project open in two tabs. Tab 1 picks categories (a has_many
// multi-select, which doesn't ship between tabs as a field edit) and
// publishes, which makes the save set `publish_at`. Tab 2 takes what tab 1
// saved; before, it kept the form it opened with, and its own save deleted
// the categories and blanked the publishing date.

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

test('a tab takes the categories and publishing date another tab saved, and its own save keeps them', async ({
  page,
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
  const tab2 = await page.context().newPage()
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

  await tab2.close()
})

// Both tabs change the categories; tab 1 saves. Tab 2 keeps its own pick
// and asks which to keep; it takes the saved one.
test('a tab that changed the categories too asks which to keep', async ({ page }) => {
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
  const tab2 = await page.context().newPage()
  await tab2.goto(url)
  await syncLV(tab2)
  await page.goto(url)
  await syncLV(page)

  for (const [tab, title] of [
    [tab2, 'Category West'],
    [page, 'Category East'],
  ]) {
    await tab.locator('#project_project_categories-field-base').getByRole('button', { name: 'Select' }).click()
    await tab.getByRole('checkbox', { name: title }).click()
    await syncLV(tab)
    await tab.getByRole('button', { name: 'OK' }).click()
    await syncLV(tab)
  }

  await saveAndContinue(page)

  const notice = tab2.getByTestId('saved-elsewhere')
  await expect(notice).toBeVisible()
  await expect(notice).toContainText('Another tab or editor saved')
  await expect(categories(tab2)).toHaveText(['Category West'])
  // Its own recovery copy is the form it shows, not one to offer it
  await expect(tab2.getByTestId('draft-notice')).toHaveCount(0)

  await notice.getByRole('button', { name: 'Use the saved version' }).click()
  await syncLV(tab2)
  await expect(notice).toHaveCount(0)
  await expect(categories(tab2)).toHaveText(['Category East'])

  await saveAndContinue(tab2)
  await tab2.reload()
  await syncLV(tab2)
  await expect(categories(tab2)).toHaveText(['Category East'])

  await tab2.close()
})
