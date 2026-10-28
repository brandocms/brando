import { test, expect } from '../../test-support/setupAuth'
import { awaitBlockDebounce, getPreviewFrame, syncLV, toggleLivePreview, waitForPreviewReady } from '../../utils'

// What an editor types as text prints as text: a string var and a heading
// show markup typed into them as written, while a rich-text var renders its
// formatting.
test.setTimeout(60000)

async function createModule(page) {
  const response = await page.request.post('/__e2e/db/factory', {
    data: {
      schema: 'Brando.Content.Module',
      creator_id: 1,
      fields: ['id'],
      attributes: {
        name: { en: 'Escaped text', no: 'Escaped text' },
        namespace: { en: 'ESCAPED TEXT', no: 'ESCAPED TEXT' },
        help_text: { en: 'Text vars and headings print as text' },
        class: 'escaped-text',
        type: 'liquid',
        code: '<section b-tpl="escaped-text"><p class="headline" title="{{ headline }}">{{ headline }}</p>{% ref refs.heading %}<div class="body">{{ body }}</div></section>',
        multi: false,
        datasource: false,
        refs: [{ name: 'heading', description: 'Heading', data: { type: 'header', data: { text: 'Heading', level: 2 } } }],
        vars: [
          { type: 'string', key: 'headline', label: 'Headline', value: 'Headline', placement: 'content', width: 'full', sequence: 0 },
          { type: 'rich_text', key: 'body', label: 'Body', value: '<p>Body</p>', placement: 'content', width: 'full', sequence: 1 },
        ],
      },
    },
  })
  expect(response.ok(), await response.text()).toBeTruthy()
}

test('markup typed into a string var or a heading previews as text, rich text as formatting', async ({ page }) => {
  await createModule(page)
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill('Escaped editor text')
  await page.getByLabel('URI', { exact: true }).fill('escaped-editor-text')
  await page.getByRole('button', { name: 'Add block', exact: true }).click()
  await page.getByRole('navigation', { name: 'Module groups' }).getByRole('button', { name: /^ESCAPED TEXT\b/ }).click()
  await page.getByRole('button', { name: 'Escaped text', exact: true }).click()
  await syncLV(page)

  await toggleLivePreview(page)
  await waitForPreviewReady(page)
  const frame = getPreviewFrame(page)
  const section = frame.locator('section[b-tpl="escaped-text"]')
  await expect(section.locator('.headline')).toHaveText('Headline')

  await page.getByLabel('Headline', { exact: true }).fill('<em>Tom</em> & "Jerry"')
  await awaitBlockDebounce(page)
  await page.locator('.header-block textarea').fill('First <b>line</b>\nSecond line')
  await awaitBlockDebounce(page)

  const body = page.locator('.block-vars .tiptap-wrapper .ProseMirror')
  await body.click()
  await body.press('ControlOrMeta+a')
  await page.keyboard.type('Formatted ')
  await page.keyboard.press('ControlOrMeta+b')
  await page.keyboard.type('body')
  await expect(body.locator('strong')).toHaveText('body')
  await syncLV(page)

  const headline = section.locator('.headline')
  await expect(headline).toHaveText('<em>Tom</em> & "Jerry"')
  await expect(headline).toHaveAttribute('title', '<em>Tom</em> & "Jerry"')
  await expect(headline.locator('em')).toHaveCount(0)

  const heading = section.locator('h2')
  await expect(heading).toContainText('First <b>line</b>')
  await expect(heading.locator('b')).toHaveCount(0)
  await expect(heading.locator('br')).toHaveCount(1)

  await expect(section.locator('.body strong')).toHaveText('body')
})
