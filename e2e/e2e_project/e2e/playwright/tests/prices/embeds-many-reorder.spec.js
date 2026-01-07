import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

test.describe('Embeds many reordering and deletion', () => {
  test('creates price category with embedded prices, reorders and deletes them', async ({
    page
  }) => {
    // Navigate to Price Categories
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Price categories' }).click()
    await page.getByRole('link', { name: 'Create new' }).click()
    await syncLV(page)

    // Set status to published
    await page.locator('label').filter({ hasText: 'Published' }).click()

    // Fill category title (use the specific ID to avoid ambiguity with price titles)
    await page.locator('#price_category_title').fill('Test Category')
    await syncLV(page)

    // The form should have a default price entry
    // Add two more prices using the "Add entry" button
    const addButton = page.locator('.add-entry-button')
    await addButton.click()
    await syncLV(page)
    await addButton.click()
    await syncLV(page)

    // Fill in the three prices
    const priceEntries = page.locator('.subform-entry')
    await expect(priceEntries).toHaveCount(3)

    // Fill first price
    await priceEntries.nth(0).getByRole('textbox', { name: 'Title' }).fill('Price A')
    await priceEntries.nth(0).getByRole('textbox', { name: 'Price' }).fill('kr 100,-')
    await syncLV(page)

    // Fill second price
    await priceEntries.nth(1).getByRole('textbox', { name: 'Title' }).fill('Price B')
    await priceEntries.nth(1).getByRole('textbox', { name: 'Price' }).fill('kr 200,-')
    await syncLV(page)

    // Fill third price
    await priceEntries.nth(2).getByRole('textbox', { name: 'Title' }).fill('Price C')
    await priceEntries.nth(2).getByRole('textbox', { name: 'Price' }).fill('kr 300,-')
    await syncLV(page)

    // Save the price category
    await page.getByTestId('submit').click()
    await syncLV(page)

    // Re-open the price category to verify data was saved
    await page.getByRole('link', { name: 'Test Category' }).click()
    await syncLV(page)

    // Verify all three prices are present
    const savedEntries = page.locator('.subform-entry')
    await expect(savedEntries).toHaveCount(3)

    // Verify order: A, B, C
    await expect(savedEntries.nth(0).getByRole('textbox', { name: 'Title' })).toHaveValue('Price A')
    await expect(savedEntries.nth(1).getByRole('textbox', { name: 'Title' })).toHaveValue('Price B')
    await expect(savedEntries.nth(2).getByRole('textbox', { name: 'Title' })).toHaveValue('Price C')

    // Test reordering: drag Price C to first position
    const priceC = savedEntries.nth(2)
    const priceA = savedEntries.nth(0)

    // Scroll into view
    await priceC.scrollIntoViewIfNeeded()
    await priceA.scrollIntoViewIfNeeded()

    // Get bounding boxes for drag handles
    const sourceBox = await priceC.locator('.subform-handle').boundingBox()
    const targetBox = await priceA.locator('.subform-handle').boundingBox()

    if (sourceBox && targetBox) {
      const sourceX = sourceBox.x + sourceBox.width / 2
      const sourceY = sourceBox.y + sourceBox.height / 2
      const targetX = targetBox.x + targetBox.width / 2
      const targetY = targetBox.y + targetBox.height / 2

      await page.mouse.move(sourceX, sourceY)
      await page.mouse.down()
      await page.waitForTimeout(100)
      await page.mouse.move(targetX, targetY, { steps: 20 })
      await page.waitForTimeout(100)
      await page.mouse.up()
    }

    await syncLV(page)

    // Verify new order after drag: C, A, B
    const reorderedEntries = page.locator('.subform-entry')
    await expect(reorderedEntries.nth(0).getByRole('textbox', { name: 'Title' })).toHaveValue(
      'Price C'
    )
    await expect(reorderedEntries.nth(1).getByRole('textbox', { name: 'Title' })).toHaveValue(
      'Price A'
    )
    await expect(reorderedEntries.nth(2).getByRole('textbox', { name: 'Title' })).toHaveValue(
      'Price B'
    )

    // Save and verify order persists
    await page.getByTestId('submit').click()
    await syncLV(page)

    // Re-open to verify
    await page.getByRole('link', { name: 'Test Category' }).click()
    await syncLV(page)

    // Verify persisted order: C, A, B
    const persistedEntries = page.locator('.subform-entry')
    await expect(persistedEntries).toHaveCount(3)
    await expect(persistedEntries.nth(0).getByRole('textbox', { name: 'Title' })).toHaveValue(
      'Price C'
    )
    await expect(persistedEntries.nth(1).getByRole('textbox', { name: 'Title' })).toHaveValue(
      'Price A'
    )
    await expect(persistedEntries.nth(2).getByRole('textbox', { name: 'Title' })).toHaveValue(
      'Price B'
    )

    // Test deletion: remove Price A (now in middle position)
    // Use evaluate to trigger the button click like in table-rows test
    await persistedEntries.nth(1).locator('.subform-delete').evaluate(btn => btn.click())
    await syncLV(page)

    // Verify only 2 entries remain: C, B
    const afterDeleteEntries = page.locator('.subform-entry')
    await expect(afterDeleteEntries).toHaveCount(2)
    await expect(afterDeleteEntries.nth(0).getByRole('textbox', { name: 'Title' })).toHaveValue(
      'Price C'
    )
    await expect(afterDeleteEntries.nth(1).getByRole('textbox', { name: 'Title' })).toHaveValue(
      'Price B'
    )

    // Save and verify deletion persists
    await page.getByTestId('submit').click()
    await syncLV(page)

    // Re-open to verify
    await page.getByRole('link', { name: 'Test Category' }).click()
    await syncLV(page)

    // Verify persisted deletion: only C and B remain
    const finalEntries = page.locator('.subform-entry')
    await expect(finalEntries).toHaveCount(2)
    await expect(finalEntries.nth(0).getByRole('textbox', { name: 'Title' })).toHaveValue('Price C')
    await expect(finalEntries.nth(1).getByRole('textbox', { name: 'Title' })).toHaveValue('Price B')
  })
})
