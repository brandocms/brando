import { test, expect } from '../../test-support/setupAuth'
import { syncLV, awaitBlockDebounce } from '../../utils'

// The edit session (`Brando.EditSession`): one process per open entry puts
// every editor's block changes in one order. These run two browser contexts
// on one entry and check what each editor sees, without reloads.
test.describe('Edit session', () => {
  test.setTimeout(120000)

  const createEntryWithHeaders = async (page, title, uri, texts) => {
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill(title)
    await page.getByLabel('URI').fill(uri)

    for (const [index, text] of texts.entries()) {
      await page.getByRole('button', { name: 'Add block' }).last().click()
      await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await expect(page.locator('.module-picker-namespace.active')).toContainText('05 LIVE PREVIEW TEST')
      await page.getByRole('button', { name: 'Styled Header' }).click()
      await syncLV(page)
      const ta = page.locator('.header-block textarea').nth(index)
      await ta.fill(text)
      await ta.blur()
      await syncLV(page)
    }

    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
    await syncLV(page)
    await expect(page.locator('.header-block textarea').nth(texts.length - 1)).toHaveValue(texts.at(-1), {
      timeout: 15000,
    })

    return new URL(page.url()).pathname
  }

  const open = async (page, url) => {
    await page.goto(url)
    await syncLV(page)
    // A marker that a reload would wipe.
    await page.evaluate(() => (window.__sameDocument = true))
  }

  test('two editors in different blocks see each other type, without leaving the block', async ({
    page,
    secondUserPage,
  }) => {
    const url = await createEntryWithHeaders(page, 'Session Two Blocks', 'session-two-blocks', ['One', 'Two'])
    await open(page, url)
    await open(secondUserPage, url)

    const mine = page.locator('.header-block textarea').nth(0)
    const theirs = secondUserPage.locator('.header-block textarea').nth(1)

    await mine.click()
    await mine.fill('One, typed by A')
    await theirs.click()
    await theirs.fill('Two, typed by B')
    await awaitBlockDebounce(page)
    await awaitBlockDebounce(secondUserPage)

    // Both are still in their blocks: the changes arrive as they type.
    await expect(mine).toBeFocused()
    await expect(theirs).toBeFocused()
    await expect(page.locator('.header-block textarea').nth(1)).toHaveValue('Two, typed by B', { timeout: 5000 })
    await expect(secondUserPage.locator('.header-block textarea').nth(0)).toHaveValue('One, typed by A', {
      timeout: 5000,
    })

    expect(await page.evaluate(() => window.__sameDocument)).toBe(true)
    expect(await secondUserPage.evaluate(() => window.__sameDocument)).toBe(true)
  })

  test('a late joiner sees unsaved work, a new block included', async ({ page, secondUserPage }) => {
    const url = await createEntryWithHeaders(page, 'Session Late Join', 'session-late-join', ['Saved'])
    await open(page, url)

    const first = page.locator('.header-block textarea').nth(0)
    await first.click()
    await first.fill('Changed, not saved')
    await awaitBlockDebounce(page)

    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await expect(page.locator('.module-picker-namespace.active')).toContainText('05 LIVE PREVIEW TEST')
    await page.getByRole('button', { name: 'Styled Header' }).click()
    await syncLV(page)
    const added = page.locator('.header-block textarea').nth(1)
    await added.fill('Added, not saved')
    await awaitBlockDebounce(page)

    // B opens the entry while A is still in the new block.
    await open(secondUserPage, url)
    const theirs = secondUserPage.locator('.header-block textarea')
    await expect(theirs).toHaveCount(2)
    await expect(theirs.nth(0)).toHaveValue('Changed, not saved')
    await expect(theirs.nth(1)).toHaveValue('Added, not saved')
  })

  test('an Assistant proposal applied while another editor has the entry open arrives without a reload', async ({
    page,
    secondUserPage,
  }) => {
    // A page with a Team Section holding Alice, then Bob.
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill('Session Team')
    await page.getByLabel('URI').fill('session-team')
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
    await page.getByRole('button', { name: 'Team Section' }).click()
    await syncLV(page)

    const multi = p => p.locator('[data-module-multi="true"]').first()
    const members = p => multi(p).locator('.block-children [data-uid]')

    for (const [index, name] of ['Alice Smith', 'Bob Jones'].entries()) {
      await multi(page).locator('.block-plus').last().click()
      await page.getByRole('button', { name: 'COPY PASTE TEST' }).click()
      await page.getByRole('button', { name: /^Team Member\b/ }).click()
      await syncLV(page)
      await members(page).nth(index).locator('.block-vars').getByLabel('Name').fill(name)
      await awaitBlockDebounce(page)
    }

    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
    await syncLV(page)
    const [, id] = page.url().match(/\/admin\/pages\/update\/(\d+)/)

    // B has the entry open and changes Alice's role without saving.
    await open(secondUserPage, `/admin/pages/update/${id}`)
    await expect(members(secondUserPage)).toHaveCount(2)
    const role = members(secondUserPage).nth(0).locator('.block-vars').getByLabel('Role')
    await role.fill('Unsaved by B')
    await awaitBlockDebounce(secondUserPage)
    await secondUserPage.getByLabel('Title', { exact: true }).click()

    // A asks the assistant to put Bob first, and applies it.
    await page.goto(`/admin/assistant?content_type=Brando.Pages.Page&id=${id}&field=blocks`)
    await syncLV(page)
    const input = page.getByLabel('Message')
    await input.fill('Put the last team member first')
    await input.press('Enter')
    const review = page.locator('.assistant-proposal')
    await expect(review.getByRole('heading', { name: 'Ready for your review' })).toBeVisible({ timeout: 15000 })
    await review.getByRole('button', { name: /^Apply/ }).click()
    await expect(review.getByRole('heading', { name: 'Applied' })).toBeVisible({ timeout: 15000 })

    // B's editor follows, in place, and keeps the unsaved role.
    const names = members(secondUserPage).locator('.block-vars').getByLabel('Name')
    await expect(names.nth(0)).toHaveValue('Bob Jones', { timeout: 10000 })
    await expect(names.nth(1)).toHaveValue('Alice Smith')
    await expect(members(secondUserPage).nth(1).locator('.block-vars').getByLabel('Role')).toHaveValue('Unsaved by B')
    expect(await secondUserPage.evaluate(() => window.__sameDocument)).toBe(true)

    // B's save writes both: the assistant's order and B's role.
    await secondUserPage.getByTestId('split-dropdown-button').click()
    await secondUserPage.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(secondUserPage.locator('.draft-save-state').first()).toHaveAttribute('data-state', 'clean', {
      timeout: 15000,
    })
    await secondUserPage.reload()
    await syncLV(secondUserPage)
    await expect(members(secondUserPage)).toHaveCount(2, { timeout: 15000 })
    await expect(names.nth(0)).toHaveValue('Bob Jones')
    await expect(members(secondUserPage).nth(1).locator('.block-vars').getByLabel('Role')).toHaveValue('Unsaved by B')
  })
})
