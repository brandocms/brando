import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

async function fixture(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

async function openProject(page, content) {
  const client = await fixture(page, 'E2eProject.Projects.Client', { name: 'Havglimt', slug: 'havglimt', status: 'published', language: 'en' })
  const project = await fixture(page, 'E2eProject.Projects.Project', { title: 'Havglimt retreat', slug: 'havglimt-retreat', introduction: content, client_id: client.id, status: 'draft', language: 'en' })
  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await syncLV(page)
  const field = page.locator('[data-footnote-field="introduction"]')
  await expect(field.locator('.tiptap[contenteditable=true]')).toBeVisible()
  return { project, field, input: field.locator('.tiptap-text') }
}

test('regular form rich text is ready to edit and preserves untouched HTML', async ({ page }, testInfo) => {
  const content = '<h2>Room to read</h2><p class="lede">Our <strong>rooms</strong> &amp; gardens.</p><p>Visit <a href="/rooms">the rooms</a> or take a walk by the sea.</p>'
  await page.setViewportSize({ width: 1440, height: 1000 })
  const { project, field, input } = await openProject(page, content)
  await expect(field.locator('.tiptap-editor-shell')).toHaveCount(1)
  await expect(field.locator('.tiptap[contenteditable=true]')).toContainText('Our rooms & gardens.')
  await expect(input).toHaveValue(content)
  await field.evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }))
  await page.mouse.move(0, 0)
  await field.screenshot({ path: testInfo.outputPath('rich-text-regular-desktop.png') })
  await page.screenshot({ path: testInfo.outputPath('rich-text-form-desktop.png') })
  await page.setViewportSize({ width: 390, height: 844 })
  await field.evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }))
  await expect.poll(() => field.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true)
  await field.screenshot({ path: testInfo.outputPath('rich-text-regular-mobile.png') })
  await page.screenshot({ path: testInfo.outputPath('rich-text-form-mobile.png') })
  await page.getByLabel('Title', { exact: true }).fill('Untouched text preserved')
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/projects\/projects$/)
  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await expect(input).toHaveValue(content)
  await expect(field.locator('.tiptap[contenteditable=true]')).toContainText('Our rooms & gardens.')
  await expect(field.locator('.tiptap-editor-shell')).toHaveCount(1)
})

test('regular form rich text supports immediate save and LiveSocket rejoin', async ({ page }, testInfo) => {
  await page.setViewportSize({ width: 1440, height: 1000 })
  const { project, field, input } = await openProject(page, '<p>Original text</p>')
  await expect(field.locator('.tiptap-activate')).toHaveCount(0)
  const editor = field.locator('.tiptap[contenteditable=true]')
  await editor.click()
  await expect(editor).toBeFocused()
  await editor.press('ControlOrMeta+a')
  await page.keyboard.insertText('Saved immediately after typing')
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/projects\/projects$/)
  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await expect(input).toHaveValue('<p>Saved immediately after typing</p>')
  await editor.click()
  await expect(editor).toBeFocused()
  // Exercise form recovery on rejoin. The separate real-network-loss gap
  // (a hard reload instead of recovery) is recorded in block-recovery.spec.js.
  await page.evaluate(() => window.liveSocket.disconnect())
  await expect(page.locator('.phx-connected').first()).toBeHidden()
  await editor.press('ControlOrMeta+a')
  await page.keyboard.insertText('Recovered offline text')
  await expect(input).toHaveValue('<p>Recovered offline text</p>')
  await page.evaluate(() => window.liveSocket.connect())
  await syncLV(page)
  await expect(input).toHaveValue('<p>Recovered offline text</p>')
  await expect(field.locator('.tiptap')).toHaveText('Recovered offline text')
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/projects\/projects$/)
  await page.goto(`/admin/projects/projects/update/${project.id}`)
  await expect(input).toHaveValue('<p>Recovered offline text</p>')
  await editor.click()
  await expect(editor).toBeFocused()
  await field.screenshot({ path: testInfo.outputPath('rich-text-activated.png') })
  await field.evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }))
  await page.screenshot({ path: testInfo.outputPath('rich-text-form-active.png') })
})

for (const language of ['en', 'no']) {
  test(`block rich text preview preserves content and supports keyboard editing in ${language}`, async ({ page }, testInfo) => {
    const html = '<h2>A slower pace by the sea</h2><p class="legacy">Light-filled rooms, quiet gardens and the open water. A place to arrive, settle in and stay a little longer.</p><p>Explore <a href="/rooms">our rooms</a> and find your favourite corner of Havglimt.</p>'
    const refs = [{ name: 'body', description: 'Main text', uid: 'preview-body', data: { type: 'text', data: { text: html, extensions: ['p', 'h2', 'bold', 'link'], type: 'paragraph' } } }]
    await fixture(page, 'Brando.Content.Module', {
      name: { en: 'Introduction', no: 'Introduksjon' }, namespace: { en: 'Content', no: 'Innhold' },
      help_text: { en: 'Page introduction' }, class: 'introduction', type: 'liquid',
      code: '<article>{% ref refs.body %}</article>', refs, vars: [], multi: false, datasource: false,
    })
    await page.goto('/admin/pages/create')
    await syncLV(page)
    await page.getByLabel('Title', { exact: true }).fill('Havglimt — a slower pace')
    await page.getByLabel('URI', { exact: true }).fill('havglimt')
    await page.getByRole('button', { name: 'Add block', exact: true }).click()
    await page.getByRole('button', { name: /^Content \d+$/ }).click()
    await page.getByRole('button', { name: 'Introduction', exact: true }).click()
    await syncLV(page)
    await page.getByTestId('split-dropdown-button').click()
    await page.getByRole('button', { name: /Save and continue editing/ }).click()
    await expect(page).toHaveURL(/\/admin\/pages\/update\/\d+/)
    const url = page.url()
    if (language === 'no') expect((await page.request.post('/e2e/setup_fixtures/norwegian-admin-user')).ok()).toBe(true)
    await page.setViewportSize({ width: 1440, height: 1000 })
    await page.goto(url)
    await syncLV(page)
    const field = page.locator('[data-tiptap-type="block"]').first()
    const button = field.locator('.tiptap-activate')
    await expect(button).toContainText(language === 'no' ? 'Rediger tekst' : 'Edit text')
    await expect(field.locator('.tiptap-editor-shell')).toHaveCount(0)
    await expect(field.locator('.tiptap-text')).toHaveValue(html)
    for (const width of [1440, 390]) {
      await page.setViewportSize({ width, height: 1000 })
      await field.evaluate(el => el.scrollIntoView({ block: 'center', behavior: 'instant' }))
      await page.mouse.move(0, 0)
      await expect.poll(() => field.evaluate(el => el.scrollWidth <= el.clientWidth)).toBe(true)
      await page.screenshot({ path: testInfo.outputPath(`block-text-preview-${language}-${width}.png`) })
    }
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/pages$/)
    await page.goto(url)
    await expect(field.locator('.tiptap-text')).toHaveValue(html)
    await button.focus()
    await button.press('Enter')
    const editor = field.locator('[contenteditable=true]')
    await expect(editor).toBeFocused()
    await editor.press('ControlOrMeta+a')
    await page.keyboard.insertText('A new introduction, ready to save.')
    const editedHTML = await field.locator('.tiptap-text').inputValue()
    expect(editedHTML).toContain('A new introduction, ready to save.')
    await page.getByTestId('submit').click()
    await expect(page).toHaveURL(/\/admin\/pages$/)
    await page.goto(url)
    await expect(field.locator('.tiptap-text')).toHaveValue(editedHTML)
  })
}

test('a saved block with 155 rich text refs opens without mounting editors', async ({ page }, testInfo) => {
  const refs = Array.from({ length: 155 }, (_, index) => ({
    name: `text_${index}`, description: `Text ${index}`, uid: `lazy-ref-${index}`,
    data: { type: 'text', data: { text: `<p>Passage ${index}: <strong>formatted text</strong> and a <a href="/rooms">link</a>.</p>`, extensions: [], type: 'paragraph' } },
  }))
  await fixture(page, 'Brando.Content.Module', {
    name: { en: 'Many text fields' }, namespace: { en: 'Performance' }, help_text: { en: '155 rich text fields' },
    class: 'many-text-fields', type: 'liquid', code: refs.map(ref => `{% ref refs.${ref.name} %}`).join(''),
    refs, vars: [], multi: false, datasource: false,
  })
  await page.setViewportSize({ width: 1440, height: 1000 })
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill('Many text fields')
  await page.getByLabel('URI', { exact: true }).fill('many-text-fields')
  await page.getByRole('button', { name: 'Add block', exact: true }).click()
  await page.getByRole('button', { name: /^Performance/ }).click()
  await page.getByRole('button', { name: 'Many text fields', exact: true }).click()
  await expect(page.locator('.tiptap-preview')).toHaveCount(155)
  await expect(page.locator('.tiptap-editor-shell')).toHaveCount(0)
  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/pages$/)
  const url = await page.getByRole('link', { name: 'Many text fields', exact: true }).getAttribute('href')
  const start = Date.now()
  await page.goto(url)
  await expect(page.locator('.tiptap-preview')).toHaveCount(155)
  await syncLV(page)
  const metrics = { loadMs: Date.now() - start, ...await page.evaluate(() => ({
    nodes: document.querySelectorAll('*').length,
    editors: document.querySelectorAll('.tiptap-editor-shell').length,
    inputs: document.querySelectorAll('.tiptap-text').length,
  })) }
  expect(metrics.editors).toBe(0)
  expect(metrics.inputs).toBe(155)
  console.log('155-ref block editor:', JSON.stringify(metrics))
  await testInfo.attach('155-ref-load.json', { body: JSON.stringify(metrics), contentType: 'application/json' })
  await page.locator('.tiptap-preview').first().scrollIntoViewIfNeeded()
  await page.screenshot({ path: testInfo.outputPath('rich-text-blocks-desktop.png') })
  await page.locator('.tiptap-activate').first().click()
  await expect(page.locator('.tiptap-editor-shell')).toHaveCount(1)
  await expect(page.locator('.tiptap[contenteditable=true]')).toBeFocused()
  await expect(page.locator('.tiptap-text').last()).toHaveValue(refs[154].data.data.text)
})
