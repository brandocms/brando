const { test, expect } = require('../../../e2e/e2e/playwright/node_modules/@playwright/test')

async function setup(page, options = {}) {
  await page.goto('/tiptap.html')
  await page.waitForFunction(() => !!window.harness)
  await page.evaluate(options => harness.create(options), options)
  await expect(page.locator('.ProseMirror')).toBeVisible()
}
const html = page => page.evaluate(() => harness.current.editor.getHTML())
const command = (page, name, ...args) => page.evaluate(({ name, args }) => harness.current.editor.commands[name](...args), { name, args })

for (const [name, options, target] of [
  ['block form', { formTarget: '42' }, '42'],
  ['explicit editor target', { formTarget: '42', editorTarget: '43' }, '43'],
  ['LiveView form', {}, null],
]) {
  test(`nested editor routes link requests and replies to its ${name}`, async ({ page }) => {
    await setup(page, { ...options, nestedComponent: '99', content: '<p>Oslo</p>' })
    await page.locator('.ProseMirror').click()
    await command(page, 'selectAll')
    await page.getByRole('button', { name: 'Link', exact: true }).click()
    expect(await page.evaluate(() => harness.current.sent.find(e => e.name === 'tiptap_link_dialog').target)).toBe(target)
    await page.evaluate(() => {
      const c = harness.current, request = c.sent.find(e => e.name === 'tiptap_link_dialog').payload
      c.emit('set_link', { request_id: request.request_id, href: '/oslo', mark_type: 'link', link_text: 'Oslo' })
    })
    expect(await page.evaluate(() => harness.current.sent.find(e => e.name === 'tiptap_link_result'))).toMatchObject({ target, payload: { applied: true } })
    expect(await html(page)).toContain('href="/oslo"')
  })
}

test('nested editor routes footnotes, commits and AI to its current form owner', async ({ page }) => {
  await setup(page, { nestedComponent: '99', formTarget: '42', content: '<p>Oslo</p>' })
  await page.locator('.ProseMirror').click()
  await command(page, 'setTextSelection', 5)
  await page.getByRole('button', { name: 'Add footnote', exact: true }).click()
  await page.evaluate(() => harness.current.emit('insert_footnote', { uid: 'oslo-note' }))
  await page.getByRole('button', { name: 'Edit footnote 1', exact: true }).click()
  const sent = await page.evaluate(() => harness.current.sent)
  for (const name of ['focus', 'create_footnote', 'commit_tiptap', 'open_footnote']) {
    expect(sent.find(e => e.name === name)).toMatchObject({ target: '42' })
  }
  expect(sent.findLast(e => e.name === 'commit_tiptap').payload.form).toContain('oslo-note')

  // The next event must use the patched form target, not a CID cached at mount.
  await page.evaluate(() => harness.current.form.setAttribute('phx-target', '44'))
  await page.getByRole('button', { name: 'Write with AI', exact: true }).click()
  await page.getByRole('button', { name: 'Generate suggestion', exact: true }).click()
  await page.getByRole('button', { name: 'Cancel', exact: true }).click()
  expect(await page.evaluate(() => harness.current.sent.find(e => e.name === 'tiptap_ai_generate'))).toMatchObject({ target: '44' })
  expect(await page.evaluate(() => harness.current.sent.find(e => e.name === 'tiptap_ai_cancel'))).toMatchObject({ target: '44' })
})

test('link dialog acknowledges success only after the owning form commits the HTML', async ({ page }) => {
  await setup(page, { formTarget: '42', nestedComponent: '99', footnotes: false, deferCommits: true, content: '<p>Oslo</p>' })
  await command(page, 'selectAll')
  await page.getByRole('button', { name: 'Link', exact: true }).click()
  await page.evaluate(() => {
    const c = harness.current, request = c.sent.find(e => e.name === 'tiptap_link_dialog').payload
    c.emit('set_link', { request_id: request.request_id, href: '/oslo', mark_type: 'link', link_text: 'Oslo' })
  })
  const pending = await page.evaluate(() => harness.current.sent)
  const commit = pending.find(e => e.name === 'commit_tiptap')
  expect(commit.target).toBe('42')
  expect(new URLSearchParams(commit.payload.form).get('page[body]')).toContain('href="/oslo"')
  expect(pending.some(e => e.name === 'tiptap_link_result')).toBe(false)
  await page.evaluate(() => harness.current.commitReplies.shift()({}))
  expect(await page.evaluate(() => harness.current.sent.at(-1))).toMatchObject({
    name: 'tiptap_link_result', target: '42', payload: { applied: true },
  })
})

test('writing focus uses the editor frame and toolbar keyboard focus stays visible', async ({ page }) => {
  await setup(page)
  const editor = page.locator('.ProseMirror'), shell = page.locator('.tiptap-editor-shell')
  await editor.click()
  await expect(editor).toBeFocused()
  await expect(editor).toHaveCSS('outline-style', 'none')
  await expect(shell).not.toHaveCSS('box-shadow', 'none')
  await editor.press('Alt+F10')
  const button = page.getByRole('toolbar').locator('button:focus')
  await expect(button).toBeFocused()
  await expect(button).toHaveCSS('outline-style', 'solid')
  await page.getByRole('button', { name: 'After editor', exact: true }).focus()
  await expect(shell).toHaveCSS('box-shadow', 'none')
})

test('list input rules, Tab and Shift-Tab use one ProseMirror runtime', async ({ page }) => {
  await setup(page, { content: '<p></p>' })
  const doc = page.locator('.ProseMirror')
  await doc.click(); await page.keyboard.type('1. First'); await page.keyboard.press('Enter'); await page.keyboard.type('Second')
  await expect(doc.locator('ol > li')).toHaveCount(2)
  await page.keyboard.press('Tab'); await expect(doc.locator('ol ol li')).toHaveCount(1)
  await page.keyboard.press('Shift+Tab'); await expect(doc.locator('ol > li')).toHaveCount(2)
  await command(page, 'setContent', '<p></p>'); await doc.click(); await page.keyboard.type('- Bullet')
  await expect(doc.locator('ul li')).toHaveCount(1)
  expect(await page.evaluate(() => harness.errors)).toEqual([])
})

test('restrictions gate shortcuts/commands while preserving legacy HTML', async ({ page }) => {
  await setup(page, { extensions: 'p|bold', content: '<h6>Legacy heading</h6><blockquote><p>Old quote</p></blockquote><p><u>Underlined</u></p>' })
  expect(await html(page)).toContain('<h6>Legacy heading</h6>')
  expect(await command(page, 'toggleUnderline')).toBe(false)
  expect(await command(page, 'toggleBlockquote')).toBe(false)
  expect(await command(page, 'setHeading', { level: 2 })).toBe(false)
  await command(page, 'setContent', '<p></p>'); await page.locator('.ProseMirror').click(); await page.keyboard.type('> Plain')
  expect(await html(page)).toBe('<p>&gt; Plain</p>')
  await page.keyboard.press(process.platform === 'darwin' ? 'Meta+b' : 'Control+b'); await page.keyboard.type(' bold')
  expect(await html(page)).toContain('<strong>')
})

test('blockquote is available only with explicit configuration', async ({ page }) => {
  await setup(page, { extensions: 'p|blockquote', content: '<p></p>' })
  await page.locator('.ProseMirror').click(); await page.keyboard.type('> Quote')
  expect(await html(page)).toContain('<blockquote>')
})

test('buttons share URL validation and round-trip extra classes without nested links', async ({ page }) => {
  await setup(page, { content: '<p><a class="action-button extra" href="/rooms" data-identifier-id="12">Rooms</a></p>' })
  expect(await html(page)).toContain('action-button extra')
  await command(page, 'selectAll')
  expect(await command(page, 'setButton', { href: 'javascript:void(0)' })).toBe(false)
  expect(await command(page, 'setLink', { href: 'javascript:void(0)' })).toBe(false)
  await command(page, 'setLink', { href: '/safe', class: null })
  expect((await html(page)).match(/<a /g)).toHaveLength(1)
  expect(await html(page)).toContain('data-identifier-id="12"')
})

test('footnote insertion preserves selected words and uses a mapped insertion position', async ({ page }) => {
  await setup(page, { content: '<p>Selected words remain.</p>' })
  await command(page, 'setTextSelection', { from: 1, to: 9 })
  await page.getByRole('button', { name: 'Add footnote', exact: true }).click()
  await page.evaluate(() => harness.current.emit('insert_footnote', { uid: 'note-1' }))
  expect(await html(page)).toBe('<p>Selected<sup data-footnote-uid="note-1">•</sup> words remain.</p>')
})

test('echoes retain history; real replacement resets it without recreating editor/listeners', async ({ page }) => {
  await setup(page)
  await command(page, 'insertContent', 'New ')
  expect(await page.evaluate(() => harness.current.editor.can().undo())).toBe(true)
  const result = await page.evaluate(() => {
    const { hook, editor, handlers } = harness.current
    const before = handlers.size
    hook.remount(); hook.remount(); hook.updated()
    const same = hook._editor === editor && handlers.size === before && editor.can().undo()
    hook.replaceContent({ html: '<p>Remote revision</p>', revision: 5 })
    hook.replaceContent({ html: '<p>Stale</p>', revision: 4 })
    return { same, undo: editor.can().undo(), html: editor.getHTML() }
  })
  expect(result).toEqual({ same: true, undo: false, html: '<p>Remote revision</p>' })
  await page.evaluate(() => harness.current.hook.destroyed())
  expect(await page.evaluate(() => harness.app.components.length)).toBe(0)
})

test('anchors retain readable IDs across formatting and can be removed at a caret', async ({ page }) => {
  await setup(page, { content: '<p><span data-type="jump-anchor" id="getting-here">Arrival information</span></p>' })
  await command(page, 'setTextSelection', { from: 3, to: 8 }); await command(page, 'toggleBold')
  expect((await html(page)).match(/id="getting-here"/g)).toHaveLength(1)
  await command(page, 'setTextSelection', 4); await command(page, 'unsetJumpAnchor')
  expect(await html(page)).not.toContain('getting-here')
})

test('named styles remain distinct and visual clearing retains links and anchors', async ({ page }) => {
  await setup(page, { styles: [{ element: 'span', class: 'foo-bar', label: 'First' }, { element: 'span', class: 'foo_bar', label: 'Second' }], content: '<p><span data-type="jump-anchor" id="here"><a href="/here"><span class="foo-bar">First</span> <span class="foo_bar">Second</span></a></span></p>' })
  const before = await html(page)
  expect(before).toContain('class="foo-bar"'); expect(before).toContain('class="foo_bar"'); expect(before).not.toContain('style_')
  await command(page, 'selectAll'); await page.getByRole('button', { name: 'More formatting', exact: true }).click(); await page.getByRole('menuitem', { name: 'Remove text formatting' }).click()
  const after = await html(page)
  expect(after).toContain('id="here"'); expect(after).toContain('href="/here"'); expect(after).not.toContain('class="foo')
})

test('paste converts inline emphasis and preserves deliberate link targets', async ({ page }) => {
  await setup(page)
  const result = await page.evaluate(() => {
    const editor = harness.current.editor
    return editor.options.editorProps.transformPastedHTML('<p class="foreign"><span style="font-weight:700;font-style:italic">Hello</span> <a href="/same" target="_self">same tab</a></p>')
  })
  expect(result).toContain('<strong>'); expect(result).toContain('<em>'); expect(result).toContain('target="_self"'); expect(result).not.toContain('foreign')
})

test('AI stays out of HTML until acceptance and supports discard and one-step undo', async ({ page }) => {
  await setup(page)
  const original = await html(page)
  await page.getByRole('button', { name: 'Write with AI', exact: true }).click(); await page.getByRole('button', { name: 'Generate suggestion', exact: true }).click()
  await page.evaluate(() => { const request = harness.current.sent.findLast(event => event.name === 'tiptap_ai_generate'); harness.current.emit('ai', { request_id: request.payload.request_id, text: 'A calmer introduction.' }) })
  await expect(page.getByRole('region', { name: 'AI suggestion' })).toBeVisible()
  expect(await html(page)).toBe(original)
  expect(await page.locator('.tiptap-text').inputValue()).toBe(original)
  await page.getByRole('button', { name: 'Accept', exact: true }).click()
  expect(await html(page)).toBe('<p>A calmer introduction.</p>')
  await command(page, 'undo'); expect(await html(page)).toBe(original)
})

test('AI ignores late replies and cannot overwrite text changed during generation', async ({ page }) => {
  await setup(page)
  await page.getByRole('button', { name: 'Write with AI', exact: true }).click(); await page.getByRole('button', { name: 'Generate suggestion' }).click()
  await command(page, 'insertContent', 'Changed ')
  await page.evaluate(() => { const request = harness.current.sent.findLast(event => event.name === 'tiptap_ai_generate'); harness.current.emit('ai', { request_id: request.payload.request_id, text: 'Stale suggestion' }) })
  await expect(page.getByRole('button', { name: 'Accept', exact: true })).toHaveCount(0)
  expect(await html(page)).toContain('Changed')
  await page.getByRole('button', { name: 'Discard', exact: true }).click()
  await expect(page.getByRole('region', { name: 'AI suggestion' })).toHaveCount(0)
})

test('expanded mode retains editor identity, content and undo history', async ({ page }) => {
  await setup(page)
  await command(page, 'insertContent', 'Edit ')
  await page.getByRole('button', { name: 'Expand editor', exact: true }).click()
  await expect(page.getByRole('dialog', { name: 'Introduction', exact: true })).toBeVisible()
  await page.keyboard.press('Escape')
  expect(await page.evaluate(() => harness.current.hook._editor === harness.current.editor && harness.current.editor.can().undo())).toBe(true)
  expect(await html(page)).toContain('Edit ')
})

test('link dialog applies to captured text, preserves marks and acknowledges success', async ({ page }) => {
  await setup(page, { content: '<p>Our <strong>rooms</strong> are ready.</p>' })
  await command(page, 'setTextSelection', { from: 5, to: 10 })
  await page.getByRole('button', { name: 'Link', exact: true }).click()
  await page.evaluate(() => {
    const current = harness.current
    const request = current.sent.find(event => event.name === 'tiptap_link_dialog').payload
    current.emit('set_link', { request_id: request.request_id, href: '/rooms', target: null, mark_type: 'link', link_text: 'rooms' })
  })
  expect(await html(page)).toContain('<strong>rooms</strong></a>')
  expect(await page.evaluate(() => harness.current.sent.at(-1).payload.applied)).toBe(true)
  await command(page, 'undo')
  expect(await html(page)).toBe('<p>Our <strong>rooms</strong> are ready.</p>')
})

test('canceled or stale link responses cannot replace newer words', async ({ page }) => {
  await setup(page, { content: '<p>Original words</p>' })
  await command(page, 'selectAll')
  await page.getByRole('button', { name: 'Link', exact: true }).click()
  await command(page, 'insertContent', 'New words')
  await page.evaluate(() => {
    const c = harness.current, request = c.sent.find(e => e.name === 'tiptap_link_dialog').payload
    c.emit('set_link', { request_id: request.request_id, href: '/old', link_text: 'Original words' })
  })
  expect(await html(page)).toBe('<p>New words</p>')
  expect(await page.evaluate(() => harness.current.sent.at(-1).payload.applied)).toBe(false)
})

test('module configuration preview updates tools while preserving legacy text and styles', async ({ page }) => {
  await setup(page, { extensions: 'p', content: '<p class="lede"><span class="old-style">Existing copy</span></p>' })
  await expect(page.getByRole('button', { name: 'Bold', exact: true })).toHaveCount(0)
  await page.evaluate(async () => {
    const c = harness.current
    c.hook.el.dataset.tiptapExtensions = 'p|bold|orderedList'
    c.hook.updated()
  })
  await expect(page.getByRole('button', { name: 'Bold', exact: true })).toBeVisible()
  expect(await html(page)).toContain('class="old-style"')
  expect(await html(page)).toContain('class="lede"')
  expect(await page.evaluate(() => harness.app.components.length)).toBe(1)
})

test('presence locks prevent keyboard edits and restore editability on release', async ({ page }) => {
  await setup(page)
  const before = await html(page)
  await page.evaluate(() => harness.current.hook.el.closest('.field-wrapper').classList.add('field-locked'))
  await expect(page.locator('.ProseMirror')).toHaveAttribute('contenteditable', 'false')
  await expect(page.getByRole('button', { name: 'Bold', exact: true })).toBeDisabled()
  expect(await html(page)).toBe(before)
  await page.evaluate(() => harness.current.hook.el.closest('.field-wrapper').classList.remove('field-locked'))
  await expect(page.locator('.ProseMirror')).toHaveAttribute('contenteditable', 'true')
})

test('color control reflects parsed RGB and resets without clearing the link', async ({ page }) => {
  await setup(page, { content: '<p><a href="/rooms"><span style="color: rgb(255, 0, 0)">Red rooms</span></a></p>' })
  await command(page, 'setTextSelection', 4)
  await page.getByRole('button', { name: 'More formatting' }).click()
  await expect(page.getByLabel('Text color', { exact: true })).toHaveValue('#ff0000')
  await page.getByRole('menuitem', { name: 'Reset color' }).click()
  expect(await html(page)).toContain('href="/rooms"')
})

test('AI can replace an inline passage and undo it without changing its neighbors', async ({ page }) => {
  await setup(page, { content: '<p>Before old wording after.</p>' })
  await command(page, 'setTextSelection', { from: 8, to: 19 })
  await page.getByRole('button', { name: 'Write with AI' }).click()
  await page.getByRole('button', { name: 'Generate suggestion' }).click()
  await page.evaluate(() => {
    const c = harness.current, request = c.sent.find(e => e.name === 'tiptap_ai_generate').payload
    c.emit('ai', { request_id: request.request_id, text: 'new wording' })
  })
  await page.getByRole('button', { name: 'Accept', exact: true }).click()
  expect(await html(page)).toBe('<p>Before new wording after.</p>')
  await command(page, 'undo')
  expect(await html(page)).toBe('<p>Before old wording after.</p>')
})

test('anchor paste cannot create a duplicate and foreign footnotes become visible text', async ({ page }) => {
  await setup(page, { content: '<p><span id="Getting-here" data-type="jump-anchor">First</span></p><p>Second</p>' })
  await command(page, 'focus', 'end')
  await page.evaluate(() => harness.current.editor.view.pasteHTML('<p><span id="Getting-here" data-type="jump-anchor">Copied</span><sup data-footnote-uid="foreign">1</sup></p>'))
  expect((await html(page)).match(/id="Getting-here"/g)).toHaveLength(1)
  expect(await html(page)).not.toContain('data-footnote-uid="foreign"')
  expect(await html(page)).toContain('[note]')
  await expect(page.getByRole('status')).toContainText('Unsupported content')
})

test('long-document editing keeps the HTML mirror current and records transaction costs', async ({ page }) => {
  await page.goto('/tiptap.html')
  await page.waitForFunction(() => !!window.harness)
  const timing = await page.evaluate(async () => {
    const content = Array.from({ length: 600 }, (_, i) => `<p>Paragraph ${i}. A considered place by the sea with room to slow down, read, and enjoy the changing light.</p>`).join('')
    const started = performance.now()
    await harness.create({ content, footnotes: false })
    const mounted = performance.now() - started
    harness.current.editor.commands.focus('end')
    const samples = []
    for (let index = 0; index < 30; index++) {
      const start = performance.now()
      harness.current.editor.commands.insertContent('x')
      samples.push(performance.now() - start)
    }
    samples.sort((a, b) => a - b)
    return { mountedMs: Math.round(mounted), medianMs: samples[15], p95Ms: samples[28], htmlBytes: harness.current.input.value.length, mirrorCurrent: harness.current.input.value === harness.current.editor.getHTML() }
  })
  expect(timing.mirrorCurrent).toBe(true)
  expect(timing.p95Ms).toBeLessThan(500)
  console.log('Tiptap 600-paragraph benchmark:', JSON.stringify(timing))
})

test('keyboard menus preserve focus and Escape closes only the nested menu', async ({ page }) => {
  await setup(page, { extensions: 'p|h2|bold|list|orderedList', ai: false })
  const doc = page.locator('.ProseMirror')
  await doc.click(); await doc.press('Alt+F10')
  await expect(page.getByRole('button', { name: 'Paragraph and style' })).toBeFocused()
  await page.keyboard.press('Enter'); await page.keyboard.press('ArrowDown'); await page.keyboard.press('Enter')
  await expect(doc.locator('h2')).toHaveCount(1)
  await expect(doc).toBeFocused()
  await page.getByRole('button', { name: 'Expand editor' }).click()
  await page.getByRole('button', { name: 'Done', exact: true }).focus()
  await page.keyboard.press('Tab')
  await expect(page.getByRole('button', { name: 'Paragraph and style' })).toBeFocused()
  await page.getByRole('button', { name: 'List types' }).click()
  await page.keyboard.press('Escape')
  await expect(page.getByRole('button', { name: 'List types' })).toBeFocused()
  await expect(page.locator('.tiptap-editor-shell.expanded')).toHaveCount(1)
  await page.keyboard.press('Escape')
  await expect(page.locator('.tiptap-editor-shell.expanded')).toHaveCount(0)
  await expect(doc).toBeFocused()
})

test('many editors keep edits local and measure editing with neighboring instances', async ({ page }) => {
  await page.goto('/tiptap.html')
  await page.waitForFunction(() => !!window.harness)
  const timing = await page.evaluate(async () => {
    for (let index = 0; index < 20; index++) await harness.create({ footnotes: false, ai: false })
    const neighbors = harness.app.components.slice(0, -1)
    const before = neighbors.map(hook => hook._editor.getHTML())
    const samples = []
    for (let index = 0; index < 30; index++) {
      const start = performance.now()
      harness.current.editor.commands.insertContent('x')
      samples.push(performance.now() - start)
    }
    samples.sort((a, b) => a - b)
    return { medianMs: samples[15], p95Ms: samples[28], neighborsUnchanged: neighbors.every((hook, index) => hook._editor.getHTML() === before[index]), mirrorCurrent: harness.current.input.value === harness.current.editor.getHTML() }
  })
  expect(timing.neighborsUnchanged).toBe(true)
  expect(timing.mirrorCurrent).toBe(true)
  expect(timing.p95Ms).toBeLessThan(500)
  console.log('Tiptap 20-editor benchmark:', JSON.stringify(timing))
})
