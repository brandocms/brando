import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Runs against E2eProject.AssistantModel: "Put the last team member first"
// reads the selected entry's outline, where a multi block lists its entries
// as children, and moves the last child before the first. The review shows
// the order the proposal leaves the entries in, and the entry it switches off.

test('reorders the entries of a multi block and reviews the new order', async ({ page }, testInfo) => {
  test.setTimeout(120000)
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  await page.setViewportSize({ width: 1440, height: 1000 })

  // A page with a Team Section holding Alice, then Bob.
  await page.goto('/admin')
  await page.getByRole('link', { name: 'Pages & Sections' }).click()
  await syncLV(page)
  await page.getByRole('link', { name: 'Create page' }).click()
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill('Assistant Team')
  await page.getByLabel('URI').fill('assistant-team')

  await page.getByRole('button', { name: 'Add block' }).last().click()
  await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
  await page.getByRole('button', { name: 'Team Section' }).click()
  await syncLV(page)

  const multiBlock = page.locator('[data-module-multi="true"]').first()
  await expect(multiBlock).toBeVisible()

  for (const [index, name] of ['Alice Smith', 'Bob Jones'].entries()) {
    await multiBlock.locator('.block-plus').last().click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: /^Team Member\b/ }).click()
    await syncLV(page)
    const member = multiBlock.locator('.block-children [data-uid]').nth(index)
    await member.locator('.block-vars').getByLabel('Name').fill(name)
    await page.waitForTimeout(400)
    await syncLV(page)
  }

  await page.getByRole('button', { name: 'Save', exact: true }).click()
  await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
  await syncLV(page)
  await page.getByRole('link', { name: 'Assistant Team', exact: true }).click()
  await syncLV(page)
  const [, id] = page.url().match(/\/admin\/pages\/update\/(\d+)/)

  // The assistant works on the saved entry.
  await page.goto(`/admin/assistant?content_type=Brando.Pages.Page&id=${id}&field=blocks`)
  await syncLV(page)
  const input = page.getByLabel('Message')
  await input.fill('Put the last team member first and switch off the first one')
  await input.press('Enter')
  await expect(page.locator('.assistant-text').last()).toContainText('moves the last team member first', {
    timeout: 15000
  })

  const review = page.locator('.assistant-proposal')
  await expect(review.getByRole('heading', { name: 'Ready for your review' })).toBeVisible()
  await expect(review.locator('.assistant-counts')).toContainText('1 moved block')
  await expect(review.locator('.assistant-counts')).toContainText('1 changed block')

  // One card shows the order the entries end up in, with the moved one marked.
  const order = review.locator('.assistant-order')
  await expect(review).toContainText('New order in “Team Section”')
  await expect(order.locator('li')).toHaveCount(2)
  await expect(order.locator('li').nth(0)).toContainText('Bob Jones')
  await expect(order.locator('li').nth(0)).toHaveClass(/is-moved/)
  await expect(order.locator('li').nth(0)).toContainText('Moved')
  await expect(order.locator('li').nth(1)).toContainText('Alice Smith')
  await expect(order.locator('li').nth(1)).not.toHaveClass(/is-moved/)

  // Switching a block off keeps it: the card says so.
  const off = review.locator('.assistant-change-title.is-removal')
  await expect(off).toContainText('Turn off “Team Member”')
  await expect(off).toContainText('Alice Smith')
  await expect(review).toContainText('It is kept, but not shown on the page.')
  await page.screenshot({ path: testInfo.outputPath('assistant-order-desktop.png'), fullPage: true })

  // Leaving the switch-off out makes version 2 with only the new order, and
  // the conversation records it.
  const removal = review.locator('.assistant-changes > li').filter({ has: page.locator('.assistant-change-title.is-removal') })
  await removal.hover()
  await removal.getByRole('button', { name: 'Leave out' }).click()
  await expect(review.locator('.assistant-eyebrow')).toContainText('version 2')
  await expect(review.locator('.assistant-change-title.is-removal')).toHaveCount(0)
  await expect(page.locator('.assistant-bubble').last()).toContainText('Left out of the proposal')

  await review.getByRole('button', { name: /^Apply/ }).click()
  await expect(review.getByRole('heading', { name: 'Applied' })).toBeVisible({ timeout: 15000 })

  // The saved entry has Bob first.
  await page.goto(`/admin/pages/update/${id}`)
  await syncLV(page)
  const saved = page.locator('[data-module-multi="true"]').first().locator('.block-children [data-uid]')
  await expect(saved).toHaveCount(2, { timeout: 15000 })
  await expect(saved.nth(0).locator('.block-vars').getByLabel('Name')).toHaveValue('Bob Jones')
  await expect(saved.nth(1).locator('.block-vars').getByLabel('Name')).toHaveValue('Alice Smith')
  await expect(saved.nth(1).locator('.base-block').first()).not.toHaveClass(/disabled/)

  // Undo, after confirming, puts Alice first again.
  await page.goBack()
  await syncLV(page)
  page.once('dialog', dialog => dialog.accept())
  await review.getByRole('button', { name: 'Undo' }).click()
  await expect(review.getByRole('heading', { name: 'Undone' })).toBeVisible({ timeout: 15000 })

  await page.goto(`/admin/pages/update/${id}`)
  await syncLV(page)
  const restored = page.locator('[data-module-multi="true"]').first().locator('.block-children [data-uid]')
  await expect(restored.nth(0).locator('.block-vars').getByLabel('Name')).toHaveValue('Alice Smith', { timeout: 15000 })
  await expect(restored.nth(1).locator('.block-vars').getByLabel('Name')).toHaveValue('Bob Jones')
  expect(errors).toEqual([])
})
