import { test, expect } from '../../test-support/setupAuth'
import { syncLV, setEntryStatus } from '../../utils'

test.describe('Embeds many reordering and deletion', () => {
  test('creates price category with embedded prices, reorders and deletes them', async ({
    page
  }) => {
    // Navigate to Price Categories
    await page.goto('/admin')
    await page.locator('#nav-sections').getByRole('link', { name: 'Price categories' }).click()
    await page.getByRole('link', { name: 'Create new' }).click()
    await syncLV(page)

    // Set status to published
    await setEntryStatus(page, 'published')

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
    await priceEntries.nth(0).getByRole('textbox', { name: 'Title', includeHidden: true }).fill('Price A')
    await priceEntries.nth(0).getByRole('textbox', { name: 'Price' }).fill('kr 100,-')
    await syncLV(page)

    // Fill second price
    await priceEntries.nth(1).getByRole('textbox', { name: 'Title', includeHidden: true }).fill('Price B')
    await priceEntries.nth(1).getByRole('textbox', { name: 'Price' }).fill('kr 200,-')
    await syncLV(page)

    // Fill third price
    await priceEntries.nth(2).getByRole('textbox', { name: 'Title', includeHidden: true }).fill('Price C')
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
    await expect(savedEntries.nth(0).getByRole('textbox', { name: 'Title', includeHidden: true })).toHaveValue('Price A')
    await expect(savedEntries.nth(1).getByRole('textbox', { name: 'Title', includeHidden: true })).toHaveValue('Price B')
    await expect(savedEntries.nth(2).getByRole('textbox', { name: 'Title', includeHidden: true })).toHaveValue('Price C')

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
    await expect(reorderedEntries.nth(0).getByRole('textbox', { name: 'Title', includeHidden: true })).toHaveValue(
      'Price C'
    )
    await expect(reorderedEntries.nth(1).getByRole('textbox', { name: 'Title', includeHidden: true })).toHaveValue(
      'Price A'
    )
    await expect(reorderedEntries.nth(2).getByRole('textbox', { name: 'Title', includeHidden: true })).toHaveValue(
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
    await expect(persistedEntries.nth(0).getByRole('textbox', { name: 'Title', includeHidden: true })).toHaveValue(
      'Price C'
    )
    await expect(persistedEntries.nth(1).getByRole('textbox', { name: 'Title', includeHidden: true })).toHaveValue(
      'Price A'
    )
    await expect(persistedEntries.nth(2).getByRole('textbox', { name: 'Title', includeHidden: true })).toHaveValue(
      'Price B'
    )

    // Test deletion: remove Price A (now in middle position)
    // Use evaluate to trigger the button click like in table-rows test
    await persistedEntries.nth(1).locator('.subform-delete').evaluate(btn => btn.click())
    await syncLV(page)

    // Verify only 2 entries remain: C, B
    const afterDeleteEntries = page.locator('.subform-entry')
    await expect(afterDeleteEntries).toHaveCount(2)
    await expect(afterDeleteEntries.nth(0).getByRole('textbox', { name: 'Title', includeHidden: true })).toHaveValue(
      'Price C'
    )
    await expect(afterDeleteEntries.nth(1).getByRole('textbox', { name: 'Title', includeHidden: true })).toHaveValue(
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
    await expect(finalEntries.nth(0).getByRole('textbox', { name: 'Title', includeHidden: true })).toHaveValue('Price C')
    await expect(finalEntries.nth(1).getByRole('textbox', { name: 'Title', includeHidden: true })).toHaveValue('Price B')
  })

  // A drag sends the new order at the drop (#3805): a second editor sees it
  // while the first touches no field
  test('a dragged price reaches a second editor at the drop', async ({ page, secondUserPage }) => {
    const title = `Reorder sync ${Date.now()}`
    const titles = p => p.locator('.subform-entry input[name$="[title]"]')
    const expectTitles = (p, expected, message) =>
      expect
        .poll(() => titles(p).evaluateAll(inputs => inputs.map(input => input.value)), { message })
        .toEqual(expected)

    await page.goto('/admin')
    await page.locator('#nav-sections').getByRole('link', { name: 'Price categories' }).click()
    await page.getByRole('link', { name: 'Create new' }).click()
    await syncLV(page)
    await setEntryStatus(page, 'published')
    await page.locator('#price_category_title').fill(title)
    await page.locator('.add-entry-button').click()
    await expect(page.locator('.subform-entry')).toHaveCount(2)
    await syncLV(page)
    await page.locator('.add-entry-button').click()
    await expect(page.locator('.subform-entry')).toHaveCount(3)
    await syncLV(page)
    for (const [index, name] of ['Price A', 'Price B', 'Price C'].entries()) {
      const entry = page.locator('.subform-entry').nth(index)
      await entry.getByRole('textbox', { name: 'Title', includeHidden: true }).fill(name)
      await entry.getByRole('textbox', { name: 'Price' }).fill('kr 100,-')
    }
    await syncLV(page)
    await page.getByTestId('submit').click()
    await syncLV(page)
    await page.getByRole('link', { name: title }).click()
    await syncLV(page)
    await expectTitles(page, ['Price A', 'Price B', 'Price C'])

    await secondUserPage.goto(new URL(page.url()).pathname)
    await syncLV(secondUserPage)
    await expectTitles(secondUserPage, ['Price A', 'Price B', 'Price C'])

    const entries = page.locator('.subform-entry')
    const source = await entries.nth(2).locator('.subform-handle').boundingBox()
    const target = await entries.nth(0).locator('.subform-handle').boundingBox()
    await page.mouse.move(source.x + source.width / 2, source.y + source.height / 2)
    await page.mouse.down()
    await page.mouse.move(target.x + target.width / 2, target.y + target.height / 2, { steps: 20 })
    await page.mouse.up()

    await expectTitles(page, ['Price C', 'Price A', 'Price B'], 'the order where it was dragged')
    await expectTitles(secondUserPage, ['Price C', 'Price A', 'Price B'], 'the order the second editor sees')
  })
})
