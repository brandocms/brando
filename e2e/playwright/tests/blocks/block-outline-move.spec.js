import { test, expect } from '../../test-support/setupAuth'
import { syncLV, awaitBlockShip } from '../../utils'

// Moving a saved block from one container to another in the block outline.
// Under its new container the block is saved as a new row, and it used to
// carry only its unsaved changes there: it came back without its module,
// vars and refs.
test.describe('Block outline: moving a block between containers', () => {
  test.setTimeout(90000)
  test.use({ viewport: { width: 1280, height: 2000 } })

  const containers = page => page.locator('[data-block-type="container"]')
  const children = container => container.locator('.block-children > [data-uid]')

  const addContainer = async page => {
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: 'Container' }).click()
    await syncLV(page)
  }

  const addChild = async (page, container, group, module) => {
    await container.locator('.block-plus').first().click()
    await page.getByRole('navigation', { name: 'Module groups' }).getByRole('button', { name: group }).click()
    await page.locator('.module-picker').getByRole('button', { name: module }).click()
    await syncLV(page)
  }

  const saveAndReopen = async (page, title) => {
    await awaitBlockShip(page)
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/pages$/, { timeout: 30000 })
    await syncLV(page)
    await expect(page.locator('.alert.error')).not.toBeVisible({ timeout: 5000 })
    await page.getByRole('link', { name: title, exact: true }).click()
    await syncLV(page)
  }

  const moveTest = async (page, title, uri, position) => {
    await page.goto('/admin')
    await page.getByRole('link', { name: 'Pages & Sections' }).click()
    await syncLV(page)
    await page.getByRole('link', { name: 'Create page' }).click()
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill(title)
    await page.getByLabel('URI').fill(uri)

    // Container A holds a Single Asset block with a var set; container B a
    // Heading, so the outline lists B's children to drop into.
    await addContainer(page)
    await addChild(page, containers(page).nth(0), 'MEDIA', 'Single Asset')
    const varInput = children(containers(page).nth(0)).first().locator('.block-vars').getByLabel('String label')
    await varInput.fill('Kept across the move')
    await varInput.blur()
    await syncLV(page)

    await addContainer(page)
    await addChild(page, containers(page).nth(1), 'HEADERS', 'Heading')

    await saveAndReopen(page, title)

    const movedUid = await children(containers(page).nth(0)).first().getAttribute('data-uid')
    const targetUid = await containers(page).nth(1).getAttribute('data-block-uid')

    // Open the outline from the block field's actions.
    await page.locator('[data-ui-dropdown-toggle$="-actions-dropdown"]').first().click()
    await page.getByRole('button', { name: 'Block outline' }).click()
    await expect(page.locator(`#outline-${movedUid}`)).toBeVisible()

    // Drag the block's outline row into container B's list, `position`
    // relative to its Heading.
    const source = page.locator(`#outline-${movedUid} > .outline-item-row`)
    const targetList = page.locator(`#outline-children-${targetUid}`)
    const targetRow = targetList.locator('.outline-item-row').first()
    const sourceBox = await source.boundingBox()
    const targetBox = await targetRow.boundingBox()
    const targetY = position === 'above' ? targetBox.y + 4 : targetBox.y + targetBox.height - 4

    await page.mouse.move(sourceBox.x + sourceBox.width / 2, sourceBox.y + sourceBox.height / 2)
    await page.mouse.down()
    await page.waitForTimeout(100)
    await page.mouse.move(targetBox.x + targetBox.width / 2, targetY, { steps: 20 })
    await expect(targetList.locator(`#outline-${movedUid}`)).toHaveCount(1)
    await page.mouse.up()
    await syncLV(page)
    await page.locator('[id^="block-field-"][id$="-outline"]').getByRole('button', { name: 'Close' }).click()

    const moved = containers(page).nth(1).locator(`.block-children > [data-uid="${movedUid}"]`)
    await expect(moved).toHaveCount(1)
    await expect(children(containers(page).nth(0))).toHaveCount(0)

    await saveAndReopen(page, title)

    await expect(children(containers(page).nth(0))).toHaveCount(0)
    await expect(children(containers(page).nth(1))).toHaveCount(2)
    await expect(moved.locator('.block-vars').getByLabel('String label')).toHaveValue('Kept across the move')
  }

  test('a saved block moved below another container\'s block keeps its vars after saving', async ({ page }) => {
    await moveTest(page, 'Outline Move Below', 'outline-move-below', 'below')
  })

  // The block lands at the index it left: the move is still a move.
  test('a saved block moved to the same place in another container moves', async ({ page }) => {
    await moveTest(page, 'Outline Move Above', 'outline-move-above', 'above')
  })
})
