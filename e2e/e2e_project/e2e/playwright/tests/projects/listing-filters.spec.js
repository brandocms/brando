import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Seed data creates 3 published projects: Alpha, Beta, Gamma (none have full_case)
// We create 1 additional project with full_case: true for testing
// Total: 4 projects (all published, 1 with full_case)

test.describe('Listing Filters', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/admin')

    // Create a client first
    await page.getByRole('link', { name: 'Clients' }).click()
    await page.getByRole('link', { name: 'Create new' }).click()
    await syncLV(page)
    await page.getByText('Published').click()
    await page.getByRole('textbox', { name: 'Name' }).fill('Test Client')
    await page.getByTestId('submit').click()
    await syncLV(page)

    // Create one project with full_case: true
    await page.getByRole('link', { name: 'Projects' }).click()
    await page.getByRole('link', { name: 'Create new' }).click()
    await syncLV(page)
    await page.locator('label').filter({ hasText: 'Published' }).click()
    await page.getByRole('textbox', { name: 'Title' }).fill('Full Case Project')
    await page.getByRole('textbox', { name: 'Title' }).dispatchEvent('input')
    await page.getByRole('textbox', { name: 'Title' }).blur()
    await syncLV(page)
    // Enable full case toggle
    await page.locator('#project_full_case-field-base div').click()
    // Fill introduction
    const editor = page.locator('.tiptap-wrapper [contenteditable="true"]').first()
    await editor.click()
    await editor.pressSequentially('Full case intro', { delay: 10 })
    await editor.evaluate(el => el.blur())
    await syncLV(page)
    // Select client
    await page.locator('#project_client_id-field-base').getByRole('button', { name: 'Select' }).click()
    await page.getByRole('button', { name: 'Test Client' }).click()
    await page.getByTestId('submit').click()
    await syncLV(page)

    // Verify we're back on listing and project was created
    await expect(page).toHaveURL(/\/admin\/projects\/projects/)
    await expect(page.locator('.content-list').getByText('Full Case Project')).toBeVisible()
  })

  test('shows advanced filters bar with boolean and select filters', async ({ page }) => {
    await page.goto('/admin/projects/projects')
    await syncLV(page)

    // Check that advanced filters bar is visible
    const filtersBar = page.locator('.advanced-filters-bar')
    await expect(filtersBar).toBeVisible()

    // Check boolean filter (Full case only) is visible
    await expect(filtersBar.getByText('Full case only')).toBeVisible()

    // Check select filter (Status) is visible
    await expect(filtersBar.getByText('Status')).toBeVisible()
  })

  test('boolean filter toggles and filters list', async ({ page }) => {
    await page.goto('/admin/projects/projects')
    await syncLV(page)

    // All 4 projects should be visible initially (3 from seed + 1 full case)
    await expect(page.locator('.content-list .list-row')).toHaveCount(4)
    await expect(page.getByText('Full Case Project')).toBeVisible()

    // Click the boolean filter toggle for "Full case only"
    const booleanFilter = page.locator('.boolean-filter')
    await booleanFilter.click()
    await syncLV(page)

    // Only the full case project should be visible
    await expect(page.locator('.content-list .list-row')).toHaveCount(1)
    await expect(page.getByText('Full Case Project')).toBeVisible()

    // URL should have the filter param
    await expect(page).toHaveURL(/filter:full_case=true/)

    // Toggle off
    await booleanFilter.click()
    await syncLV(page)

    // All 4 projects should be visible again
    await expect(page.locator('.content-list .list-row')).toHaveCount(4)
  })

  test('select filter filters by status', async ({ page }) => {
    await page.goto('/admin/projects/projects')
    await syncLV(page)

    // All 4 projects should be visible initially (all are published)
    await expect(page.locator('.content-list .list-row')).toHaveCount(4)

    // Click the select filter dropdown
    const selectFilter = page.locator('.select-filter select')
    await selectFilter.selectOption('published')
    await syncLV(page)

    // All 4 projects are published, so all should still be visible
    await expect(page.locator('.content-list .list-row')).toHaveCount(4)

    // URL should have the filter param
    await expect(page).toHaveURL(/filter:status_filter=published/)

    // Select draft - no projects are drafts
    await selectFilter.selectOption('draft')
    await syncLV(page)

    // No draft projects exist
    await expect(page.locator('.content-list .list-row')).toHaveCount(0)
    await expect(page.getByText('No matching entries found')).toBeVisible()

    // Select "All" to reset
    await selectFilter.selectOption('')
    await syncLV(page)

    // All 4 projects should be visible again
    await expect(page.locator('.content-list .list-row')).toHaveCount(4)
  })

  test('text filter still works in header', async ({ page }) => {
    await page.goto('/admin/projects/projects')
    await syncLV(page)

    // All 4 projects should be visible initially
    await expect(page.locator('.content-list .list-row')).toHaveCount(4)

    // The text filter input is in .list-tools .filters
    // Type in the filter input (it's next to the filter-key button)
    const filterInput = page.locator('.list-tools .filters input[type="text"]')
    await filterInput.fill('Full Case')
    await syncLV(page)

    // Only matching project should be visible
    await expect(page.locator('.content-list .list-row')).toHaveCount(1)
    await expect(page.locator('.content-list').getByText('Full Case Project')).toBeVisible()
  })

  test('combining multiple filters (AND logic)', async ({ page }) => {
    await page.goto('/admin/projects/projects')
    await syncLV(page)

    // Enable boolean filter (full case only)
    await page.locator('.boolean-filter').click()
    await syncLV(page)

    // Should show only the 1 full case project
    await expect(page.locator('.content-list .list-row')).toHaveCount(1)
    await expect(page.getByText('Full Case Project')).toBeVisible()

    // Select published status (full case project is published)
    await page.locator('.select-filter select').selectOption('published')
    await syncLV(page)

    // Should still show the full case project (it's published AND full case)
    await expect(page.locator('.content-list .list-row')).toHaveCount(1)
    await expect(page.getByText('Full Case Project')).toBeVisible()

    // Select draft status
    await page.locator('.select-filter select').selectOption('draft')
    await syncLV(page)

    // Should show no results (no project is both draft AND full case)
    await expect(page.locator('.content-list .list-row')).toHaveCount(0)
    await expect(page.getByText('No matching entries found')).toBeVisible()
  })

  test('reset filters button clears all advanced filters', async ({ page }) => {
    await page.goto('/admin/projects/projects')
    await syncLV(page)

    // All 4 projects visible initially
    await expect(page.locator('.content-list .list-row')).toHaveCount(4)

    // Enable boolean filter
    await page.locator('.boolean-filter').click()
    await syncLV(page)

    // Only 1 full case project visible
    await expect(page.locator('.content-list .list-row')).toHaveCount(1)

    // Click reset button
    await page.locator('.reset-filters-btn').click()
    await syncLV(page)

    // All 4 projects should be visible again
    await expect(page.locator('.content-list .list-row')).toHaveCount(4)
  })

  test('filter state persists in URL (shareable)', async ({ page }) => {
    // Navigate directly with filter params
    await page.goto('/admin/projects/projects?filter:full_case=true&filter:status_filter=published')
    await syncLV(page)

    // Filters should be active
    await expect(page.locator('.boolean-filter input')).toBeChecked()
    await expect(page.locator('.select-filter select')).toHaveValue('published')

    // Only matching project should be visible (1 full case + published)
    await expect(page.locator('.content-list .list-row')).toHaveCount(1)
    await expect(page.getByText('Full Case Project')).toBeVisible()
  })
})
