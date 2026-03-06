import { test, expect } from '../../test-support/setupAuth'
import { syncLV, dragAndDrop, fillSlugSource } from '../../utils'

test.describe('Multi-select reordering', () => {
  test.beforeEach(async ({ page }) => {
    // Create a client first
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Clients' }).click()
    await page.getByRole('link', { name: 'Create new' }).click()
    await syncLV(page)
    await page.getByText('Published').click()
    const clientNameField = page.getByRole('textbox', { name: 'Name' })
    await fillSlugSource(clientNameField, 'Test Client')
    await syncLV(page)
    await expect(page.locator('input[name="client[slug]"]')).toHaveValue('test-client', { timeout: 10000 })
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/clients/)
    await syncLV(page)

    // Create three categories
    await page.getByRole('link', { name: 'Categories', exact: true }).click()
    await expect(page).toHaveURL(/\/categories/)
    await syncLV(page)
    await page.getByRole('link', { name: 'Create new' }).click()
    await syncLV(page)
    const catAField = page.getByRole('textbox', { name: 'Title' })
    await fillSlugSource(catAField, 'Category A')
    await syncLV(page)
    await expect(page.locator('input[name="category[slug]"]')).toHaveValue('category-a', { timeout: 10000 })
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/categories/)
    await syncLV(page)

    await page.getByRole('link', { name: 'Create new' }).click()
    await syncLV(page)
    const catBField = page.getByRole('textbox', { name: 'Title' })
    await fillSlugSource(catBField, 'Category B')
    await syncLV(page)
    await expect(page.locator('input[name="category[slug]"]')).toHaveValue('category-b', { timeout: 10000 })
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/categories/)
    await syncLV(page)

    await page.getByRole('link', { name: 'Create new' }).click()
    await syncLV(page)
    const catCField = page.getByRole('textbox', { name: 'Title' })
    await fillSlugSource(catCField, 'Category C')
    await syncLV(page)
    await expect(page.locator('input[name="category[slug]"]')).toHaveValue('category-c', { timeout: 10000 })
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/categories/)
    await syncLV(page)
  })

  test('reorders selected items in multi-select and persists order', async ({ page }) => {
    // Navigate to Projects and create new
    await page.getByRole('link', { name: 'Projects' }).click()
    await expect(page).toHaveURL(/\/projects\/projects/)
    await syncLV(page)
    await page.getByRole('link', { name: 'Create new' }).click()
    await syncLV(page)

    // Fill required fields
    await page.locator('label').filter({ hasText: 'Published' }).click()
    const titleField = page.getByRole('textbox', { name: 'Title' })
    await titleField.fill('Reorder Test Project')
    // Dispatch input event to trigger slug hook, then blur and wait
    await titleField.dispatchEvent('input')
    await titleField.blur()
    await syncLV(page)
    // Wait for slug field to be populated
    const slugField = page.locator('input[name="project[slug]"]')
    await expect(slugField).toHaveValue(/reorder-test-project/, { timeout: 10000 })

    // Fill introduction (required field)
    // Use pressSequentially instead of fill() for TipTap contenteditable elements
    // fill() doesn't reliably trigger TipTap's input handlers
    const editor = page.locator('.tiptap-wrapper [contenteditable="true"]').first()
    await expect(editor).toBeVisible()
    await editor.click()
    await editor.pressSequentially('Test introduction', { delay: 10 })
    // Wait for TipTap to process input, then blur to trigger sync with hidden input
    await page.waitForTimeout(100)
    await editor.evaluate(el => el.blur())
    // Wait for hidden input to sync and LiveView to process the change
    await page.waitForTimeout(200)
    await syncLV(page)

    // Select client
    await page
      .locator('#project_client_id-field-base')
      .getByRole('button', { name: 'Select' })
      .click()
    await page.getByRole('button', { name: 'Test Client' }).click()
    await syncLV(page)

    // Open multi-select modal
    await page
      .locator('#project_project_categories-field-base')
      .getByRole('button', { name: 'Select' })
      .click()
    await syncLV(page)

    // Select categories in order: A, B, C
    await page.getByRole('button', { name: 'Category A' }).click()
    await syncLV(page)
    await page.getByRole('button', { name: 'Category B' }).click()
    await syncLV(page)
    await page.getByRole('button', { name: 'Category C' }).click()
    await syncLV(page)

    // Close modal
    await page.getByRole('button', { name: 'OK' }).click()
    await syncLV(page)

    // Verify the sortable container exists with the hook
    const sortableContainer = page.locator(
      '#project_project_categories-selected-options[data-sequenced]'
    )
    await expect(sortableContainer).toBeVisible()

    // Verify initial order in selected labels
    const selectedLabels = sortableContainer.locator('.selected-label')
    await expect(selectedLabels).toHaveCount(3)
    await expect(selectedLabels.nth(0)).toContainText('Category A')
    await expect(selectedLabels.nth(1)).toContainText('Category B')
    await expect(selectedLabels.nth(2)).toContainText('Category C')

    // Drag Category C to first position (before Category A)
    const categoryC = selectedLabels.filter({ hasText: 'Category C' })
    const categoryA = selectedLabels.filter({ hasText: 'Category A' })

    // Ensure elements are in viewport and get fresh bounding boxes
    await categoryA.scrollIntoViewIfNeeded()
    await page.waitForTimeout(200)

    const sourceBox = await categoryC.boundingBox()
    const targetBox = await categoryA.boundingBox()

    if (sourceBox && targetBox) {
      const sourceX = sourceBox.x + sourceBox.width / 2
      const sourceY = sourceBox.y + sourceBox.height / 2
      const targetX = targetBox.x + targetBox.width / 2
      const targetY = targetBox.y + targetBox.height / 2

      await page.mouse.move(sourceX, sourceY)
      await page.waitForTimeout(200)
      await page.mouse.down()
      await page.waitForTimeout(200)
      await page.mouse.move(targetX, targetY, { steps: 10 })
      await page.waitForTimeout(200)
      await page.mouse.up()
    }

    await syncLV(page)

    // Verify new order after drag: C, A, B
    const reorderedLabels = page.locator(
      '#project_project_categories-selected-options .selected-label'
    )
    await expect(reorderedLabels.nth(0)).toContainText('Category C')
    await expect(reorderedLabels.nth(1)).toContainText('Category A')
    await expect(reorderedLabels.nth(2)).toContainText('Category B')

    // Save the project
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/projects\/projects/)
    await syncLV(page)

    // Re-open the project to verify order persisted
    await page.getByRole('link', { name: 'Reorder Test Project' }).click()
    await syncLV(page)

    // Verify order persisted: C, A, B
    const persistedLabels = page.locator(
      '#project_project_categories-selected-options .selected-label'
    )
    await expect(persistedLabels).toHaveCount(3)
    await expect(persistedLabels.nth(0)).toContainText('Category C')
    await expect(persistedLabels.nth(1)).toContainText('Category A')
    await expect(persistedLabels.nth(2)).toContainText('Category B')
  })
})
