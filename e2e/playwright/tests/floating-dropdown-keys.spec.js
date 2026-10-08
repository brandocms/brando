import { test, expect } from '../test-support/setupAuth'
import { syncLV, confirmUploadFolder } from '../utils'

// The action menus of `Brando.FloatingDropdown` take a menu button's keys:
// opening moves the focus to the first action, ArrowDown/ArrowUp move and
// wrap, Home/End jump, Enter/Space choose, Escape closes and gives the focus
// back to the trigger. The actions keep a roving tabindex.

const focused = page => page.evaluate(() => document.activeElement?.textContent.replace(/\s+/g, ' ').trim())

async function itemNames(menu) {
  return menu.locator('button:not(:disabled), a[href]').evaluateAll(items =>
    items.filter(item => item.checkVisibility()).map(item => item.textContent.replace(/\s+/g, ' ').trim()))
}

// Walks a menu that is open with the focus on its first action.
async function walk(page, menu, names) {
  const last = names.length - 1
  await expect.poll(() => focused(page)).toBe(names[0])
  for (const name of names.slice(1)) {
    await page.keyboard.press('ArrowDown')
    expect(await focused(page)).toBe(name)
  }
  // Wraps both ways
  await page.keyboard.press('ArrowDown')
  expect(await focused(page)).toBe(names[0])
  await page.keyboard.press('ArrowUp')
  expect(await focused(page)).toBe(names[last])
  await page.keyboard.press('Home')
  expect(await focused(page)).toBe(names[0])
  await page.keyboard.press('End')
  expect(await focused(page)).toBe(names[last])

  // Roving tabindex: only the focused action is in the tab order
  const tabindexes = await menu.locator('button:not(:disabled), a[href]').evaluateAll(items =>
    items.filter(item => item.checkVisibility()).map(item => item.getAttribute('tabindex')))
  expect(tabindexes).toEqual(names.map((_name, index) => (index === last ? '0' : '-1')))
}

test("the entry toolbar's More menu works from the keyboard", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 900 })
  await page.goto('/admin/pages/update/1')
  await syncLV(page)

  const more = page.locator('.form-tab-builtins').getByRole('button', { name: 'More', exact: true })
  const menu = page.locator('.form-tool-more-menu')

  // Enter on the trigger opens the menu with the focus on the first action
  await more.focus()
  await page.keyboard.press('Enter')
  await expect(menu).toBeVisible()
  await expect(more).toHaveAttribute('aria-expanded', 'true')
  const names = await itemNames(menu)
  expect(names.length).toBeGreaterThan(1)
  await walk(page, menu, names)

  // Escape closes it and gives the focus back
  await page.keyboard.press('Escape')
  await expect(menu).toBeHidden()
  await expect(more).toBeFocused()
  await expect(more).toHaveAttribute('aria-expanded', 'false')

  // ArrowUp on the closed trigger opens it at the last action
  await page.keyboard.press('ArrowUp')
  await expect(menu).toBeVisible()
  await expect.poll(() => focused(page)).toBe(names[names.length - 1])

  // Tab leaves the menu, which closes
  await page.keyboard.press('Tab')
  await expect(menu).toBeHidden()

  // Enter chooses: Languages opens the alternates drawer
  await more.focus()
  await page.keyboard.press('ArrowDown')
  await expect.poll(() => focused(page)).toBe(names[0])
  await page.keyboard.press('Home')
  expect(await focused(page)).toBe('Languages')
  await page.keyboard.press('Enter')
  await expect(menu).toBeHidden()
  await expect(page.getByRole('heading', { name: 'Alternates', exact: true })).toBeVisible()
})

test("the image drawer's Replace and More menus work from the keyboard", async ({ page }) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/projects/projects/update/3')
  await syncLV(page)
  const field = page.locator('#project_listing_image-media')
  await field.locator('input[type=file]').setInputFiles('./fixtures/image.jpg')
  await confirmUploadFolder(page)
  await expect(field.locator('img')).toBeVisible({ timeout: 30000 })
  await field.getByRole('button', { name: 'Configure', exact: true }).click()
  const drawer = page.getByRole('dialog', { name: 'Image details', exact: true })

  // More: a click opens it, with the focus on the first action
  const moreTrigger = drawer.getByRole('button', { name: 'More image actions', exact: true })
  const more = drawer.locator('#image-drawer-more-menu')
  await moreTrigger.click()
  await expect(more).toBeVisible()
  await walk(page, more, await itemNames(more))
  await page.keyboard.press('Escape')
  await expect(more).toBeHidden()
  await expect(moreTrigger).toBeFocused()
  await expect(drawer).toBeVisible()

  // Replace: ArrowDown on the trigger opens it; Space chooses
  const replace = drawer.getByRole('button', { name: 'Replace', exact: true })
  const menu = drawer.locator('#image-drawer-replace-menu')
  await replace.focus()
  await page.keyboard.press('ArrowDown')
  await expect(menu).toBeVisible()
  const names = await itemNames(menu)
  expect(names).toContain('Select image')
  await walk(page, menu, names)
  await page.keyboard.press('Home')
  while ((await focused(page)) !== 'Select image') await page.keyboard.press('ArrowDown')
  await page.keyboard.press(' ')
  await expect(menu).toBeHidden()
  await expect(page.getByRole('dialog', { name: 'Images', exact: true })).toBeVisible()
})
