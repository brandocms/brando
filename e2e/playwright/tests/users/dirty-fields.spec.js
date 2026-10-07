import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// Entry text inputs carry phx-debounce="300".
const awaitFieldDebounce = async (page) => {
  await page.waitForTimeout(350)
  await syncLV(page)
}

// Two editors on one entry (two browser contexts sharing a sandbox session).
// Another editor's changes that have not reached this form yet are marked on
// the field's label; they reach it when that editor leaves the field or saves.
test.describe('Unsaved fields of other editors', () => {
  test.use({ actionTimeout: 20000 })
  test.setTimeout(120000)

  const ENTRY = '/admin/pages/update/1'

  const open = async (page) => {
    await page.goto(ENTRY)
    await syncLV(page)
    await expect(page.getByLabel('Title', { exact: true })).toBeVisible()
  }

  const fieldLabel = (page, name) => page.locator(`.brando-form [data-field-presence="${name}"]`)

  const saveAndContinue = async (page) => {
    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await syncLV(page)
    await expect(page.locator('.alert.error')).not.toBeVisible()
  }

  test('a field another editor is typing in is marked until it reaches this form', async ({
    page,
    secondUserPage,
  }, testInfo) => {
    await open(page)
    await open(secondUserPage)

    const aTitle = page.getByLabel('Title', { exact: true })
    const bTitleLabel = fieldLabel(secondUserPage, 'page[title]')

    await aTitle.click()
    await aTitle.fill('Unsaved title by A')
    await awaitFieldDebounce(page)

    await expect(bTitleLabel).toHaveAttribute('data-dirty-label', /^Unsaved changes by /)
    await expect(bTitleLabel).toHaveAttribute('data-presence-color-index', /^[0-5]$/)
    await expect(fieldLabel(page, 'page[title]')).not.toHaveAttribute('data-dirty-by')

    // B's own edits re-render B's form; the mark must survive the patches.
    const bUri = secondUserPage.getByLabel('URI', { exact: true })
    await bUri.click()
    await bUri.fill('uri-by-b')
    await awaitFieldDebounce(secondUserPage)
    await expect(bTitleLabel).toHaveAttribute('data-dirty-by')
    await bTitleLabel.locator('xpath=ancestor::fieldset[1]').screenshot({
      path: testInfo.outputPath('dirty-field-mark.png'),
    })

    // A leaves the field: the title ships to B and the mark goes.
    await aTitle.blur()
    await syncLV(page)
    await expect(secondUserPage.getByLabel('Title', { exact: true })).toHaveValue('Unsaved title by A')
    await expect(bTitleLabel).not.toHaveAttribute('data-dirty-by')
  })

  test('a field changed without focus stays marked until saved, also when changed back', async ({
    page,
    secondUserPage,
  }) => {
    await open(page)
    await open(secondUserPage)

    const status = (p, value) => p.locator(`.radios-wrapper.status input[value="${value}"]`)
    const pickStatus = async (p, label) => {
      await p.locator('.radios-wrapper.status').getByText(label, { exact: true }).click()
      await syncLV(p)
    }
    const bStatusLabel = fieldLabel(secondUserPage, 'page[status]')

    // Status radios send no focus/blur events, so nothing ships right away.
    await pickStatus(page, 'Pending')
    await expect(bStatusLabel).toHaveAttribute('data-dirty-label', /^Unsaved changes by /)
    await expect(status(secondUserPage, 'pending')).not.toBeChecked()

    // Joining asks the editors present for their unsaved state.
    await secondUserPage.reload()
    await syncLV(secondUserPage)
    await expect(status(secondUserPage, 'pending')).toBeChecked()
    await expect(bStatusLabel).not.toHaveAttribute('data-dirty-by')

    // Draft is the saved status. Changing back is a change B has not seen:
    // B still holds Pending and would save it.
    await pickStatus(page, 'Draft')
    await expect(bStatusLabel).toHaveAttribute('data-dirty-by')

    await saveAndContinue(page)
    await expect(bStatusLabel).not.toHaveAttribute('data-dirty-by')
    await expect(status(secondUserPage, 'draft')).toBeChecked()
  })

  test("a peer's earlier ship does not overwrite the field I am typing in", async ({
    page,
    secondUserPage,
  }) => {
    await open(page)
    await open(secondUserPage)

    const aTitle = page.getByLabel('Title', { exact: true })
    const aUri = page.getByLabel('URI', { exact: true })
    const bTitle = secondUserPage.getByLabel('Title', { exact: true })
    const bUri = secondUserPage.getByLabel('URI', { exact: true })

    // A edits the title and moves on: the title ships to B.
    await aTitle.click()
    await aTitle.fill('Title by A')
    await awaitFieldDebounce(page)
    await aUri.click()
    await syncLV(page)
    await expect(bTitle).toHaveValue('Title by A')

    // B corrects the title and stays in the field.
    await bTitle.click()
    await bTitle.fill('Title by B')
    await awaitFieldDebounce(secondUserPage)

    // A edits the URI and leaves it. A ships its whole changeset, which still
    // holds A's own, older title.
    await aUri.fill('uri-by-a')
    await awaitFieldDebounce(page)
    await aUri.blur()
    await syncLV(page)
    await expect(bUri).toHaveValue('uri-by-a')

    // B leaves the title: B's text must survive and reach A.
    await bTitle.blur()
    await syncLV(secondUserPage)
    await expect(bTitle).toHaveValue('Title by B')
    await expect(aTitle).toHaveValue('Title by B')

    // A saves last and must not put its old title back.
    await saveAndContinue(page)
    await page.reload()
    await syncLV(page)
    await expect(page.getByLabel('Title', { exact: true })).toHaveValue('Title by B')
  })
})
