import { test, expect } from '../test-support/setupAuth'
import { serverLatency } from '../test-support/latency'
import { syncLV, setEntryStatus } from '../utils'

test.beforeEach(async ({ page }) => {
  await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.emulateMedia({ reducedMotion: 'no-preference' })
})

// Most E2E tests deliberately use 1ms CSS transitions. These tests exercise
// real motion, including changing direction while a transition is running.
async function realMotion(page) {
  await page.evaluate(() => document.body.removeAttribute('data-env'))
}

test('tabs switch before replies, keep edits through patches, and save normally', async ({ page }) => {
  const latency = await serverLatency(page)
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  await realMotion(page)
  const tabs = page.locator('.form-tab-customs')
  const content = tabs.getByRole('button', { name: 'Innhold', exact: true })
  const advanced = tabs.getByRole('button', { name: 'Avansert', exact: true })

  latency.set(1500)
  await page.getByLabel('Tittel', { exact: true }).fill('My smooth editor')
  await advanced.click()
  await expect(advanced).toHaveAttribute('aria-pressed', 'true', { timeout: 500 })
  await expect(page.locator('.form-tab[data-tab-name="Advanced"]')).toBeVisible({ timeout: 500 })
  // Rapid repeated changes must keep the most recent choice, even after a
  // validation reply from the previous tab arrives.
  await content.click()
  await advanced.click()
  latency.set(0)
  await syncLV(page)
  await expect(advanced).toHaveAttribute('aria-pressed', 'true')
  await content.click()
  await expect(page.getByLabel('Tittel', { exact: true })).toHaveValue('My smooth editor')
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL('/admin/pages')
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  await expect(page.getByLabel('Tittel', { exact: true })).toHaveValue('My smooth editor')
})

test('entry tabs leave nested create-entry form panels under their own control', async ({ page }) => {
  await page.goto('/admin/pages/create')
  await syncLV(page)
  // Input.Select and custom field components can render their own form-tab
  // panels. Reproduce that component markup without changing the page schema.
  await page.locator('.main-form > .form-tab').first().evaluate(el => {
    const nested = document.createElement('div')
    nested.id = 'nested-create-entry-panel'
    nested.className = 'form-tab active'
    nested.dataset.tabName = 'Create entry'
    nested.innerHTML = '<input aria-label="Nested entry name" value="Pending entry">'
    el.appendChild(nested)
  })
  await page.locator('.form-tab-customs').getByRole('button', { name: 'Avansert', exact: true }).click()
  await page.locator('.form-tab-customs').getByRole('button', { name: 'Innhold', exact: true }).click()
  await expect(page.getByLabel('Nested entry name')).toBeVisible()
  await expect(page.getByLabel('Nested entry name')).toHaveValue('Pending entry')
})

// Issue #1996: a submitted form announces what failed, and a keyboard user is
// moved to an error they can reach. Correcting the field clears the
// announcement: form_validation_a11y_test.exs.
test('a failed save marks the field invalid, announces why, overrides the local tab and focuses the field', async ({ page }) => {
  await page.goto('/admin/pages/create')
  await syncLV(page)
  // Required attributes are not validated while an entry is a draft, and a new
  // page starts as one — so publish it first, or the blank save succeeds.
  await setEntryStatus(page, 'published')
  const title = page.getByLabel('Tittel', { exact: true })
  // Nothing has been typed, so nothing is invalid yet — a blank create form
  // must not read as a form full of errors. It is announced as required.
  await expect(title).not.toHaveAttribute('aria-invalid', 'true')
  await expect(title).toHaveAttribute('aria-required', 'true')
  // The message container exists before it has anything to say: a live region
  // added together with its content is not reliably announced.
  const errors = page.locator('#page_title-error')
  await expect(errors).toHaveAttribute('role', 'alert')
  // Instructions first, then the message — the order they should be read in.
  await expect(title).toHaveAttribute('aria-describedby', 'page_title-instructions page_title-error')
  await page.locator('.form-tab-customs').getByRole('button', { name: 'Avansert', exact: true }).click()
  await page.getByTestId('submit').click()
  await syncLV(page)
  await expect(page.locator('[data-form-tab="Content"]')).toHaveAttribute('aria-pressed', 'true')
  await expect(title).toBeVisible()
  await expect(title).toHaveAttribute('aria-invalid', 'true')
  await expect(errors).not.toBeEmpty()
  // The save error is a modal alert, so focus waits for it to be dismissed.
  const alert = page.locator('dialog.admin-dialog')
  await alert.getByRole('button', { name: 'OK', exact: true }).click()
  await expect(alert).toBeHidden()
  // The caret lands in the offending control, not on the submit button —
  // and `aria-describedby` means arriving there reads the message out.
  await expect(title).toBeFocused()
})

for (const [name, triggerSelector, menuSelector] of [
  ['More', '.form-tab-builtins .form-tool-more-trigger', '.form-tool-more-menu'],
  ['Config', '.block-field-dropdown-toggle', '.block-field-dropdown-content']
]) {
  test(`${name} menus animate at real speed and can reopen during their exit`, async ({ page }, testInfo) => {
    await page.goto('/admin/pages/update/1')
    await syncLV(page)
    await realMotion(page)
    const more = page.locator(triggerSelector)
    const menu = page.locator(menuSelector)
    await more.click()
    await expect(menu).toBeVisible()
    expect(await menu.evaluate(el => el.getAnimations().some(a => a.transitionProperty === 'opacity'))).toBe(true)
    await expect(menu).toHaveCSS('transition-duration', '0.3s, 0.3s, 0.3s, 0.3s')
    // Finish the entrance, then reverse an actual in-progress exit. This would
    // fail if a delayed hide from the first close won over the second open.
    await menu.evaluate(el => Promise.allSettled(el.getAnimations().map(a => a.finished)))
    await page.keyboard.press('Escape')
    await expect(more).toHaveAttribute('aria-expanded', 'false')
    // The box remains painted during its exit. Its actions must keep their
    // vertical layout after :popover-open stops matching.
    const exitRows = await menu.evaluate(el => [...el.querySelectorAll('button, a')].map(action => {
      const box = action.getBoundingClientRect()
      return { top: box.top, bottom: box.bottom, height: box.height }
    }))
    expect(exitRows.length).toBeGreaterThan(1)
    expect(exitRows.every((row, index) => row.height > 0 && (index === 0 || row.top >= exitRows[index - 1].bottom - 1))).toBe(true)
    await more.press('ArrowDown')
    await expect(more).toHaveAttribute('aria-expanded', 'true')
    await menu.evaluate(el => Promise.allSettled(el.getAnimations().map(a => a.finished)))
    await expect(menu).toBeVisible()
    await expect.poll(() => menu.evaluate(el => el.contains(document.activeElement))).toBe(true)
    await page.screenshot({ path: testInfo.outputPath('editor-menu-desktop.png') })
    await page.keyboard.press('Escape')
    await expect(menu).toBeHidden()
    await expect(more).toBeFocused()

    await page.emulateMedia({ reducedMotion: 'reduce' })
    await more.click()
    await expect(menu).toHaveCSS('transition-duration', '0.001s, 0.001s, 0.001s, 0.001s')
    await page.keyboard.press('Escape')
    await expect(menu).toBeHidden()
    // The admin preference works independently of the OS preference.
    await page.emulateMedia({ reducedMotion: 'no-preference' })
    await page.evaluate(() => document.documentElement.dataset.reducedMotion = 'true')
    await more.click()
    await expect(menu).toHaveCSS('transition-duration', '0.001s, 0.001s, 0.001s, 0.001s')
  })
}

test('block configuration closes locally and keeps edited values on reopen', async ({ page }, testInfo) => {
  const latency = await serverLatency(page)
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByRole('button', { name: 'Legg til blokk', exact: true }).last().click()
  await page.getByRole('button', { name: 'Konfigvariabler', exact: true }).click()
  await syncLV(page)
  await realMotion(page)
  const block = page.locator('.entry-block [data-block-uid]').first()
  const open = async () => {
    await block.locator('.block-action-dropdown > .block-action').first().click()
    await block.locator('.block-action-dropdown-content').getByRole('button', { name: 'Konfigurer', exact: true }).click()
  }
  await open()
  const modal = page.locator('.modal.visible')
  await modal.getByLabel('Beskrivelse av blokk', { exact: true }).fill('Keep this description')
  await modal.getByLabel('Config note', { exact: true }).fill('Keep this setting')
  await syncLV(page)
  await page.screenshot({ path: testInfo.outputPath('block-config-desktop.png') })
  await page.setViewportSize({ width: 390, height: 844 })
  await expect(modal.locator('.modal-dialog')).toBeInViewport()
  await page.screenshot({ path: testInfo.outputPath('block-config-mobile.png') })

  latency.set(1500)
  await modal.getByRole('button', { name: 'Ferdig', exact: true }).click()
  await expect(modal).toBeHidden({ timeout: 700 })
  latency.set(0)
  await syncLV(page)
  await page.setViewportSize({ width: 1440, height: 1000 })
  await open()
  await expect(modal.getByLabel('Beskrivelse av blokk', { exact: true })).toHaveValue('Keep this description')
  await expect(modal.getByLabel('Config note', { exact: true })).toHaveValue('Keep this setting')
})

test('reduced motion closes the modal shell immediately and returns focus', async ({ page }) => {
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await realMotion(page)
  await page.emulateMedia({ reducedMotion: 'reduce' })
  const opener = page.locator('#page_language-field-base').getByRole('button', { name: 'Velg', exact: true })
  await opener.click()
  const modal = page.locator('.modal:visible')
  await expect(modal).toBeVisible()
  await syncLV(page)
  const elapsed = await modal.evaluate(el => new Promise(resolve => {
    const start = performance.now()
    window.liveSocket.execJS(el, el.dataset.modalClose)
    const check = () => {
      if (!el.checkVisibility()) resolve(performance.now() - start)
      else requestAnimationFrame(check)
    }
    requestAnimationFrame(check)
  }))
  expect(elapsed).toBeLessThan(150)
  await expect(opener).toBeFocused()
})

test('modal movement is painted and leaves no transform after settling', async ({ page }) => {
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await realMotion(page)
  await page.evaluate(() => {
    document.addEventListener('phx:show-start', event => {
      queueMicrotask(() => {
        const panel = event.target.querySelector(':scope > .modal-dialog')
        const animation = panel.getAnimations()[0]
        window.motionTestDuration = animation.effect.getComputedTiming().duration
        animation.pause()
        animation.currentTime = 100
        window.motionTestTransform = getComputedStyle(panel).transform
        animation.play()
      })
    }, { capture: true, once: true })
  })
  await page.locator('#page_language-field-base').getByRole('button', { name: 'Velg', exact: true }).click()
  const panel = page.locator('.modal:visible > .modal-dialog')
  const during = await page.evaluate(() => window.motionTestTransform)
  expect(await page.evaluate(() => window.motionTestDuration)).toBe(350)
  expect(during).toBeDefined()
  expect(during).not.toBe('none')
  expect(during).not.toBe('matrix(1, 0, 0, 1, 0, 0)')
  await panel.evaluate(el => Promise.allSettled(el.getAnimations().map(a => a.finished)))
  await expect(panel).toHaveCSS('transform', 'none')
})

test('a drawer can reverse while it is closing without a late hide', async ({ page }) => {
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  await realMotion(page)
  const opener = page.locator('.form-tab-customs').getByRole('button', { name: 'Meta', exact: true })
  await opener.click()
  const drawer = page.locator('.drawer[id$="-meta-drawer"]')
  await expect(drawer).toBeVisible()
  await drawer.evaluate(el => Promise.allSettled(el.getAnimations().map(a => a.finished)))
  await opener.evaluate(async el => {
    el.click()
    await new Promise(resolve => setTimeout(resolve, 80))
    el.click()
  })
  await expect(drawer).toBeVisible()
  await drawer.evaluate(el => Promise.allSettled(el.getAnimations().map(a => a.finished)))
  // Wait for the old close's deadline as well as the new entrance.
  await expect(drawer).toBeVisible()
  await drawer.getByRole('button', { name: 'Lukk', exact: true }).click()
  await expect(drawer).toBeHidden()
  await expect(opener).toBeFocused()
})

test('Meta sections ease the drawer width and fade the new pane', async ({ page }) => {
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  await realMotion(page)
  await page.locator('.form-tool-meta').click()
  const drawer = page.locator('.drawer[id$="-meta-drawer"]')
  await drawer.evaluate(el => Promise.allSettled(el.getAnimations().map(a => a.finished)))
  await page.getByTestId('meta-tab-previews').click()
  await expect(drawer).toHaveClass(/previews-open/)
  expect(await drawer.evaluate(el => el.getAnimations().some(a => a.transitionProperty === 'width'))).toBe(true)
  await expect(drawer.locator('.meta-drawer-previews')).toHaveCSS('animation-name', 'ui-content-in')
  await page.getByTestId('meta-tab-meta').click()
  await expect(drawer.locator('.meta-drawer-fields')).toBeVisible()
})

test('select rows stay still when pressed and show the chosen label before the reply', async ({ page }) => {
  const latency = await serverLatency(page)
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await realMotion(page)
  await page.locator('[data-form-tab="Advanced"]').click()
  await page.locator('#page_template-field-base').getByRole('button', { name: 'Velg', exact: true }).click()
  const modal = page.locator('.modal:visible')
  await modal.evaluate(el => Promise.allSettled(el.getAnimations({ subtree: true }).map(a => a.finished)))
  const option = modal.locator('.options-option').first()
  const before = await option.boundingBox()
  await option.hover()
  await page.mouse.down()
  const pressed = await option.boundingBox()
  expect(pressed.x).toBeCloseTo(before.x, 1)
  await page.mouse.up()
  await expect(modal).toBeHidden()

  await page.locator('[data-form-tab="Content"]').click()
  const field = page.locator('#page_language-field-base')
  await field.getByRole('button', { name: 'Velg', exact: true }).click()
  const choice = modal.locator('.options-option[value="no"]')
  const label = await choice.innerText()
  latency.set(1500)
  await choice.click()
  await expect(field.locator('.select-label')).toHaveText(label, { timeout: 150 })
  latency.set(0)
  await syncLV(page)
  await expect(field.locator('.select-label')).toHaveText(label)
})

test('saving immediately after choosing a select option saves the value already displayed', async ({ page }) => {
  const latency = await serverLatency(page)
  await page.goto('/admin/config/content/containers/update/1')
  await syncLV(page)
  const field = page.locator('#container_type-field-base')
  await field.getByRole('button', { name: 'Velg', exact: true }).click()
  const modal = page.locator('.modal:visible')
  await expect(modal.locator('.options-option[value="heex"]')).toBeVisible()
  latency.set(1500)
  await modal.locator('.options-option[value="heex"]').click()
  await expect(field.locator('.select-label')).toHaveText('Heex', { timeout: 150 })
  await expect(modal).toBeHidden()
  await page.getByTestId('submit').click()
  latency.set(0)
  await expect(page).toHaveURL('/admin/config/content/containers')
  await page.goto('/admin/config/content/containers/update/1')
  await syncLV(page)
  await expect(field.locator('.select-label')).toHaveText('Heex')
})

test('added page variables open into space without the old colour flash', async ({ page }, testInfo) => {
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await realMotion(page)
  await page.locator('[data-form-tab="Advanced"]').click()
  const vars = page.locator('.subform--vars')
  await expect(vars.locator('.vars-list')).toHaveClass(/is-empty/)
  await vars.scrollIntoViewIfNeeded()
  await vars.screenshot({ path: testInfo.outputPath('page-variables-empty.png') })
  await page.evaluate(() => {
    const animate = Element.prototype.animate
    Element.prototype.animate = function (...args) {
      const animation = animate.apply(this, args)
      if (this.matches('.vars-row')) {
        animation.pause()
        animation.currentTime = 0
        const start = this.getBoundingClientRect().height
        const background = getComputedStyle(this).backgroundColor
        animation.currentTime = 100
        const middle = this.getBoundingClientRect().height
        animation.currentTime = animation.effect.getComputedTiming().duration
        const end = this.getBoundingClientRect().height
        window.rowMotionSample = { start, middle, end, background, endBackground: getComputedStyle(this).backgroundColor }
        animation.currentTime = 0
        animation.play()
      }
      return animation
    }
  })
  await vars.getByRole('button', { name: 'Ny rad', exact: true }).click()
  await expect(vars.locator('.vars-row')).toHaveCount(1)
  const sample = await page.evaluate(() => window.rowMotionSample)
  expect(sample.start).toBeLessThan(2)
  expect(sample.middle).toBeGreaterThan(sample.start)
  expect(sample.middle).toBeLessThan(sample.end)
  expect(sample.end).toBeGreaterThan(40)
  expect(sample.background).toBe(sample.endBackground)
  await expect(vars.locator('.vars-list')).not.toHaveClass(/is-empty/)
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await vars.getByRole('button', { name: 'Ny rad', exact: true }).click()
  await expect(vars.locator('.vars-row')).toHaveCount(2)
  expect(await vars.locator('.vars-row').last().evaluate(el => el.getAnimations().filter(a => a.effect.getKeyframes().some(frame => 'height' in frame)).length)).toBe(0)
})

test('tall blocks keep their content painted through collapse and expansion', async ({ page }) => {
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByRole('button', { name: 'Legg til blokk', exact: true }).last().click()
  await page.getByRole('button', { name: /05 LIVE PREVIEW TEST/ }).click()
  await page.getByRole('button', { name: 'Stilisert overskrift', exact: true }).click()
  await syncLV(page)
  await realMotion(page)
  const block = page.locator('.base-block').first()
  const textarea = block.locator('.header-block textarea')
  await textarea.fill(Array.from({ length: 18 }, (_, i) => `Heading line ${i}`).join('\n'))
  await syncLV(page)
  const frame = block.locator(':scope > .block')
  const full = (await frame.boundingBox()).height
  expect(full).toBeGreaterThan(400)
  const sample = () => frame.evaluate(async el => {
    const animation = el.getAnimations()[0]
    if (!animation) return null
    animation.pause()
    animation.currentTime = 100
    const height = el.getBoundingClientRect().height
    const contentsVisible = getComputedStyle(el.querySelector('.block-content')).display !== 'none'
    animation.play()
    await animation.finished
    return { height, contentsVisible }
  })
  const toggle = block.locator('.block-actions label.toggler').first()
  await toggle.click()
  const closing = await sample()
  expect(closing).not.toBeNull()
  expect(closing.contentsVisible).toBe(true)
  expect(closing.height).toBeLessThan(full)
  const closed = (await frame.boundingBox()).height
  expect(closing.height).toBeGreaterThan(closed)
  await expect(textarea).toBeHidden()
  await toggle.click()
  const opening = await sample()
  expect(opening.contentsVisible).toBe(true)
  expect(opening.height).toBeGreaterThan(closed)
  expect(opening.height).toBeLessThan(full)
  await expect(textarea).toBeVisible()
  expect((await frame.boundingBox()).height).toBeCloseTo(full, 0)
  // Reverse in flight; an old completion must never collapse the new state.
  await toggle.evaluate(el => { el.click(); setTimeout(() => el.click(), 70) })
  await expect(block).not.toHaveClass(/\bcollapsed\b/)
  await expect(textarea).toBeVisible()
})

test('offline details sit below the toolbar and wrap on a phone', async ({ page }, testInfo) => {
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  await page.evaluate(() => window.liveSocket.disconnect())
  const status = page.locator('.form-save-details')
  await expect(status.locator('.draft-offline-status')).toBeVisible()
  await expect(status.locator('.draft-offline-idle')).toBeVisible()
  await expect(status.locator('.draft-offline-pending')).not.toBeVisible()
  await page.locator('input[name="page[title]"]').fill('A change while disconnected')
  await expect(status.locator('.draft-offline-idle')).not.toBeVisible()
  await expect(status.locator('.draft-offline-pending')).toBeVisible()
  await expect(page.locator('.form-tabs .draft-save-state')).toHaveCount(1)
  await expect(page.locator('.preview-chooser-trigger > .lucide-eye')).toBeVisible()
  await expect(page.locator('.preview-chooser-trigger .tab-text')).toHaveCount(0)
  for (const width of [1440, 390]) {
    await page.setViewportSize({ width, height: 1000 })
    const toolbar = await page.locator('.form-tabs').boundingBox()
    const box = await status.boundingBox()
    expect(box.y).toBeGreaterThanOrEqual(toolbar.y + toolbar.height)
    expect(await status.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true)
    await expect(page.locator('.form-tool-save-button')).toBeInViewport()
    await page.screenshot({ path: testInfo.outputPath(`offline-status-${width}.png`) })
  }
  await page.evaluate(() => window.liveSocket.connect())
  await expect(page.locator('[phx-hook="Brando.Form"]')).not.toHaveClass(/draft-pending/)
})

test('navigation fades the destination without animating form validation', async ({ page }) => {
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await realMotion(page)
  await page.evaluate(() => {
    window.addEventListener('phx:page-loading-stop', ({ detail }) => {
      if (detail.kind !== 'redirect') return
      requestAnimationFrame(() => {
        window.destinationMotion = document.getElementById('brando-main')?.getAnimations().map(a => a.effect.getComputedTiming().duration)
      })
    })
  })
  await page.locator('.entry-header a[href="/admin/pages"]').click()
  await expect(page).toHaveURL('/admin/pages')
  await expect.poll(() => page.evaluate(() => window.destinationMotion)).toContain(350)
})

test('adding a variable keeps the note button mounted and the insert control unclipped', async ({ page }) => {
  await page.goto('/admin/pages/update/1')
  await syncLV(page)
  await realMotion(page)
  await page.locator('[data-form-tab="Advanced"]').click()
  const vars = page.locator('.subform--vars')
  await vars.scrollIntoViewIfNeeded()
  const add = vars.getByRole('button', { name: 'Ny rad', exact: true })
  await vars.locator(':scope > .label-wrapper').hover()
  await expect(vars.locator(':scope > .label-wrapper .field-note-add')).toHaveCSS('opacity', '1')
  await add.hover()
  await vars.evaluate(el => {
    window.noteButtonBefore = el.querySelector('.field-note-add')
    window.noteButtonRemovals = 0
    const observer = new MutationObserver(records => {
      for (const record of records) for (const node of record.removedNodes) {
        if (node === window.noteButtonBefore || node.contains?.(window.noteButtonBefore)) window.noteButtonRemovals++
      }
    })
    observer.observe(el.querySelector(':scope > .label-wrapper'), { childList: true, subtree: true })
    const animate = Element.prototype.animate
    Element.prototype.animate = function (...args) {
      const animation = animate.apply(this, args)
      if (this.matches('.vars-row')) {
        animation.pause()
        animation.currentTime = 100
        const insert = this.querySelector('.subform-insert')
        const rect = insert.getBoundingClientRect()
        const hit = document.elementFromPoint(rect.x + rect.width / 2, rect.y + 2)
        window.insertVisibleDuringReveal = insert.contains(hit)
        animation.play()
      }
      return animation
    }
  })
  await add.click()
  await expect(vars.locator('.vars-row')).toHaveCount(1)
  await syncLV(page)
  expect(await page.evaluate(() => window.noteButtonRemovals)).toBe(0)
  expect(await page.evaluate(() => window.noteButtonBefore.isConnected)).toBe(true)
  expect(await page.evaluate(() => window.insertVisibleDuringReveal)).toBe(true)
  const insert = vars.locator('.subform-insert').first()
  expect(await insert.evaluate(el => {
    const rect = el.getBoundingClientRect()
    return el.contains(document.elementFromPoint(rect.x + rect.width / 2, rect.y + 2))
  })).toBe(true)
})

test('deleting the first variable slides it closed without replacing its neighbour', async ({ page }) => {
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.locator('[data-form-tab="Advanced"]').click()
  const vars = page.locator('.subform--vars')
  await vars.getByRole('button', { name: 'Ny rad', exact: true }).click()
  await vars.getByRole('button', { name: 'Ny rad', exact: true }).click()
  await expect(vars.locator('.vars-row')).toHaveCount(2)
  await realMotion(page)
  await page.evaluate(() => {
    const animate = Element.prototype.animate
    Element.prototype.animate = function (...args) {
      const animation = animate.apply(this, args)
      if (this.matches('.vars-row') && args[0][0].opacity === 1 && args[0][1].opacity === 0) {
        animation.pause()
        animation.currentTime = 0
        const start = this.getBoundingClientRect().height
        animation.currentTime = 100
        const middle = this.getBoundingClientRect().height
        animation.currentTime = animation.effect.getComputedTiming().duration
        window.removedRowSample = { start, middle, end: this.getBoundingClientRect().height }
        animation.currentTime = 0
        animation.play()
      }
      return animation
    }
  })
  await vars.locator('.subform-delete').first().click()
  await expect(vars.locator('.vars-row')).toHaveCount(1)
  const sample = await page.evaluate(() => window.removedRowSample)
  expect(sample.start).toBeGreaterThan(40)
  expect(sample.middle).toBeGreaterThan(sample.end)
  expect(sample.middle).toBeLessThan(sample.start)
  expect(sample.end).toBeLessThan(2)
  expect(await vars.locator('.vars-row').evaluate(el => el.getBoundingClientRect().height)).toBeGreaterThan(40)
  await page.emulateMedia({ reducedMotion: 'reduce' })
  await vars.locator('.subform-delete').click()
  await expect(vars.locator('.vars-row')).toHaveCount(0)
  await expect(vars.locator('.vars-list')).toHaveClass(/is-empty/)
})

test('the row below a deletion keeps its hover when LiveView reuses the row', async ({ page }) => {
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.locator('[data-form-tab="Advanced"]').click()
  const vars = page.locator('.subform--vars')
  await vars.getByRole('button', { name: 'Ny rad', exact: true }).click()
  await vars.getByRole('button', { name: 'Ny rad', exact: true }).click()
  await expect(vars.locator('.vars-row')).toHaveCount(2)
  await realMotion(page)
  await vars.evaluate(el => {
    window.rowHoverSamples = []
    const observer = new MutationObserver(() => {
      if (el.querySelectorAll('.vars-row').length !== 1) return
      observer.disconnect()
      const sample = () => {
        const row = el.querySelector('.vars-row')
        window.rowHoverSamples.push({
          hovered: row.matches(':hover'),
          opacity: Number(getComputedStyle(row.querySelector('.subform-delete')).opacity),
        })
        if (window.rowHoverSamples.length < 8) requestAnimationFrame(sample)
      }
      requestAnimationFrame(sample)
    })
    observer.observe(el, { childList: true, subtree: true })
  })
  await vars.locator('.subform-delete').first().click()
  await expect(vars.locator('.vars-row')).toHaveCount(1)
  await expect.poll(() => page.evaluate(() => window.rowHoverSamples.length)).toBe(8)
  const samples = await page.evaluate(() => window.rowHoverSamples)
  expect(samples.every(sample => sample.hovered)).toBe(true)
  expect(Math.min(...samples.map(sample => sample.opacity))).toBeGreaterThan(0.95)
})
