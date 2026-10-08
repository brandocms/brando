import { test, expect } from '../../test-support/setupAuth'
import { syncLV, awaitBlockDebounce } from '../../utils'

// Field presence and follow mode (#2992 step 2): two editors in one block,
// each in their own field. The edit session takes one field per op (last
// arrival wins), presence marks the field another editor is in, and an
// avatar follows that editor around the entry.
test.describe('Field presence', () => {
  test.setTimeout(120000)

  const addModule = async (page, name) => {
    await page.getByRole('button', { name: 'Add block' }).last().click()
    await page.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
    await expect(page.locator('.module-picker-namespace.active')).toContainText('05 LIVE PREVIEW TEST')
    await page.getByRole('button', { name, exact: true }).click()
    await syncLV(page)
  }

  const createPage = async (page, title, modules) => {
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill(title)
    await page.getByLabel('URI').fill(title.toLowerCase().replaceAll(' ', '-'))
    for (const module of modules) await addModule(page, module)

    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(page).toHaveURL(/\/update\//, { timeout: 30000 })
    await syncLV(page)
    await expect(page.locator('.entry-block')).toHaveCount(modules.length, { timeout: 15000 })
    return new URL(page.url()).pathname
  }

  const open = async (page, url) => {
    await page.goto(url)
    await syncLV(page)
    await expect(page.locator('.entry-block').first()).toBeVisible({ timeout: 15000 })
  }

  const block = (page, index = 0) => page.locator('.entry-block').nth(index)
  const title = (page, index = 0) => block(page, index).locator('.header-block textarea')
  const headline = (page, index = 0) => block(page, index).getByLabel('Headline', { exact: true })

  const save = async page => {
    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(page.locator('.draft-save-state').first()).toHaveAttribute('data-state', 'clean', { timeout: 15000 })
  }

  test('two editors in different fields of one block both keep their change', async ({ page, secondUserPage }) => {
    const url = await createPage(page, 'Presence Two Fields', ['HEEx Parity'])
    await open(page, url)
    await open(secondUserPage, url)

    await title(page).click()
    await title(page).fill('Title by A')
    await headline(secondUserPage).click()
    await headline(secondUserPage).fill('Headline by B')
    await awaitBlockDebounce(page)
    await awaitBlockDebounce(secondUserPage)

    // Each sees the other's field arrive while staying in their own.
    await expect(headline(page)).toHaveValue('Headline by B', { timeout: 5000 })
    await expect(title(secondUserPage)).toHaveValue('Title by A', { timeout: 5000 })
    await expect(title(page)).toBeFocused()
    await expect(headline(secondUserPage)).toBeFocused()

    // Only the field the other editor is in carries their colour.
    const theirs = block(page).locator('[data-field-presence-user]')
    await expect(theirs).toHaveCount(1, { timeout: 5000 })
    await expect(theirs.getByLabel('Headline', { exact: true })).toBeAttached()
    await expect(block(page).locator('.block-toolbar').first()).toHaveAttribute('data-presence-label', /Headline/)

    // Nothing is locked: A can still type.
    await title(page).fill('Title by A, again')
    await awaitBlockDebounce(page)
    await expect(title(secondUserPage)).toHaveValue('Title by A, again', { timeout: 5000 })

    await save(page)
    await page.reload()
    await syncLV(page)
    await expect(title(page)).toHaveValue('Title by A, again', { timeout: 15000 })
    await expect(headline(page)).toHaveValue('Headline by B')
  })

  test("rich text keeps what is typed while another editor's changes to the block arrive", async ({
    page,
    secondUserPage,
  }) => {
    const url = await createPage(page, 'Presence Rich Text', ['HEEx Parity'])
    await open(page, url)
    await open(secondUserPage, url)

    const editor = block(page).locator('[data-tiptap-type="block"] .tiptap-target [contenteditable]').first()
    await editor.click()
    await expect(editor).toHaveAttribute('contenteditable', 'true')
    await page.keyboard.press('ControlOrMeta+a')

    // A types in bursts; B's changes to the same block land between them.
    await page.keyboard.type('One ')
    await headline(secondUserPage).click()
    await headline(secondUserPage).fill('B, first')
    await page.keyboard.type('two ')
    await awaitBlockDebounce(secondUserPage)
    await page.keyboard.type('three')
    await headline(secondUserPage).fill('B, second')
    await awaitBlockDebounce(secondUserPage)
    await awaitBlockDebounce(page)

    await expect(editor).toBeFocused()
    await expect(editor).toHaveText('One two three')
    await expect(headline(page)).toHaveValue('B, second', { timeout: 5000 })
    await expect(
      block(secondUserPage).locator('[data-tiptap-type="block"] .tiptap-text').first()
    ).toHaveValue(/One two three/, { timeout: 5000 })
  })

  test('the same field: the last to type wins, without taking the focus or flickering', async ({
    page,
    secondUserPage,
  }) => {
    const url = await createPage(page, 'Presence Same Field', ['HEEx Parity'])
    await open(page, url)
    await open(secondUserPage, url)

    // Every value A's input shows while A is in it.
    await headline(page).click()
    await headline(page).evaluate(input => {
      window.__seen = new Set()
      window.__watch = setInterval(() => window.__seen.add(input.value), 10)
    })

    await headline(page).pressSequentially('A1', { delay: 30 })
    await awaitBlockDebounce(page)

    await headline(secondUserPage).click()
    await headline(secondUserPage).fill('Written by B')
    await awaitBlockDebounce(secondUserPage)
    await page.waitForTimeout(800)

    // A keeps the focus and what A typed; nothing of B's flickers in.
    await expect(headline(page)).toBeFocused()
    const seen = await page.evaluate(() => {
      clearInterval(window.__watch)
      return Array.from(window.__seen)
    })
    expect(seen.every(value => !value.includes('Written by B'))).toBe(true)

    // B typed last, so when A leaves the field it shows B's value, and so
    // does the saved entry.
    await page.getByLabel('Title', { exact: true }).click()
    await expect(headline(page)).toHaveValue('Written by B', { timeout: 5000 })
    await save(secondUserPage)
    await secondUserPage.reload()
    await syncLV(secondUserPage)
    await expect(headline(secondUserPage)).toHaveValue('Written by B', { timeout: 15000 })
  })

  test('two editors adding a block at the same place both keep theirs, in the same order', async ({
    page,
    secondUserPage,
  }) => {
    const url = await createPage(page, 'Presence Same Place', ['Styled Header', 'Styled Header'])
    await open(page, url)
    await open(secondUserPage, url)

    // Both open the module picker at the plus between the two blocks…
    // The plus above the second block
    const between = p => p.getByRole('button', { name: 'Add block' }).nth(1)
    for (const p of [page, secondUserPage]) {
      await between(p).click()
      await p.getByRole('button', { name: '05 LIVE PREVIEW TEST' }).click()
      await expect(p.locator('.module-picker-namespace.active')).toContainText('05 LIVE PREVIEW TEST')
    }

    // …and insert at once.
    await Promise.all([
      page.getByRole('button', { name: 'HEEx Parity', exact: true }).click(),
      secondUserPage.getByRole('button', { name: 'Rich Text Article', exact: true }).click(),
    ])
    await syncLV(page)
    await syncLV(secondUserPage)

    const order = p => p.locator('.entry-block').evaluateAll(blocks => blocks.map(b => b.closest('[data-block-uid]')?.dataset.blockUid))
    await expect(page.locator('.entry-block')).toHaveCount(4, { timeout: 5000 })
    await expect(secondUserPage.locator('.entry-block')).toHaveCount(4, { timeout: 5000 })
    await expect.poll(async () => JSON.stringify(await order(secondUserPage)), { timeout: 5000 }).toBe(
      JSON.stringify(await order(page))
    )

    // Both new blocks sit between the two headers.
    await expect(block(page, 0).locator('.header-block textarea')).toBeVisible()
    await expect(block(page, 3).locator('.header-block textarea')).toBeVisible()
  })

  test('following another editor scrolls to where they work until this editor scrolls', async ({
    page,
    secondUserPage,
  }) => {
    const url = await createPage(page, 'Presence Follow', [
      'HEEx Parity',
      'Styled Header',
      'Styled Header',
      'Styled Header',
      'HEEx Parity',
    ])
    await page.setViewportSize({ width: 1280, height: 700 })
    await open(page, url)
    await open(secondUserPage, url)

    // A follows B.
    const avatar = page.locator('.page-presences [data-follow-user]')
    await expect(avatar).toHaveCount(1)
    await avatar.click()
    await expect(avatar).toHaveAttribute('aria-pressed', 'true')
    await expect(page.locator('.follow-bar')).toBeVisible()

    // B goes to the last block: A's view follows.
    await headline(secondUserPage, 4).click()
    await expect(headline(page, 4)).toBeInViewport({ timeout: 5000 })

    // A scrolls: following stops.
    await page.mouse.wheel(0, -300)
    await expect(page.locator('.follow-bar')).toBeHidden()
    await expect(avatar).toHaveAttribute('aria-pressed', 'false')
    await page.waitForTimeout(500)
    const scrolled = await page.evaluate(() => window.scrollY)

    // B moves on; A stays where A is.
    await headline(secondUserPage, 0).click()
    await page.waitForTimeout(1000)
    expect(await page.evaluate(() => window.scrollY)).toBe(scrolled)
  })

  // #2992 review: a field op on a block that was new when the save read the
  // session, replayed after the save gave it rows, named those rows by uid
  // only, and the next save failed or wrote a duplicate.
  //
  // LiveView blurs the focused input while a form submit is in flight
  // (`submitForm` → `blurActiveElement`), so a key that lands in that moment
  // is lost, on main as well. The test holds the editor, the other editor
  // and the saved row to what the typist's own field ends up showing.
  test('typing, saving with the keyboard and typing on in a new block keeps it all', async ({ page, secondUserPage }) => {
    const url = await createPage(page, 'Presence Save While Typing', ['HEEx Parity'])
    await open(page, url)
    await open(secondUserPage, url)

    await addModule(page, 'HEEx Parity')
    await expect(page.locator('.entry-block')).toHaveCount(2, { timeout: 15000 })
    await expect(secondUserPage.locator('.entry-block')).toHaveCount(2, { timeout: 15000 })

    await headline(page, 1).click()
    await page.keyboard.press('ControlOrMeta+a')
    await page.keyboard.type('Before the save', { delay: 20 })
    await page.keyboard.press('ControlOrMeta+s')
    await page.keyboard.type(', and after it', { delay: 20 })
    // the save has given the new block its row
    await expect(block(page, 1)).toHaveAttribute('data-id', /\d+/, { timeout: 15000 })
    await headline(page, 1).click()
    await page.keyboard.press('End')
    await page.keyboard.type(', and more', { delay: 20 })
    await awaitBlockDebounce(page)

    const typed = await headline(page, 1).inputValue()
    expect(typed).toMatch(/^Before the save.*and more$/)
    await expect(headline(secondUserPage, 1)).toHaveValue(typed, { timeout: 10000 })

    await save(page)
    await page.reload()
    await syncLV(page)
    await expect(page.locator('.entry-block')).toHaveCount(2, { timeout: 15000 })
    await expect(headline(page, 1)).toHaveValue(typed, { timeout: 15000 })
  })

  // #2992 review: the server's answer to an earlier keystroke, arriving
  // after the last one, was put back when the editor left the field.
  test('a field typed into in bursts keeps every keystroke when the editor leaves it', async ({ page, secondUserPage }) => {
    const url = await createPage(page, 'Presence Debounced Typing', ['HEEx Parity'])
    await open(page, url)
    await open(secondUserPage, url)

    // a slow connection: the answer to a burst arrives after the next one
    await page.evaluate(() => window.liveSocket.enableLatencySim(250))
    try {
      await headline(page).click()
      await page.keyboard.press('ControlOrMeta+a')
      await page.keyboard.type('Typed', { delay: 20 })
      // the debounced change goes out…
      await page.waitForTimeout(330)
      // …and the next burst is typed before its answer is back
      await page.keyboard.type(' in bursts', { delay: 10 })
      await page.waitForTimeout(1500)
      await page.keyboard.press('Tab')
      await page.waitForTimeout(800)

      await expect(headline(page)).toHaveValue('Typed in bursts')
      await expect(headline(secondUserPage)).toHaveValue('Typed in bursts', { timeout: 5000 })
    } finally {
      await page.evaluate(() => window.liveSocket.disableLatencySim())
    }
  })
})
