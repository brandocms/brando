import { test, expect } from '../../test-support/setupAuth'
import { awaitBlockDebounce, syncLV } from '../../utils'

async function createModule(page, name, code) {
  const response = await page.request.post('/__e2e/db/factory', {
    data: {
      schema: 'Brando.Content.Module',
      creator_id: 1,
      fields: ['id'],
      attributes: {
        name: { en: name, no: name },
        namespace: { en: 'LIQUID NESTING', no: 'LIQUID NESTING' },
        help_text: { en: 'Liquid preview regression' },
        class: 'liquid-nesting',
        type: 'liquid',
        code,
        multi: false,
        datasource: false,
        refs: [{
          name: 'heading',
          description: 'Heading',
          data: { type: 'header', data: { text: 'Original heading', level: 2 } },
        }],
        vars: [{
          type: 'string', key: 'caption', label: 'Caption', value: 'Original caption',
          placement: 'content', width: 'full',
        }],
      },
    },
  })
  expect(response.ok(), await response.text()).toBeTruthy()
}

async function addModule(page, name) {
  await page.getByRole('button', { name: 'Add block', exact: true }).last().click()
  await page.getByRole('navigation', { name: 'Module groups' })
    .getByRole('button', { name: /^LIQUID NESTING\b/ }).click()
  await page.getByRole('button', { name, exact: true }).click()
  await syncLV(page)
}

test('nested Liquid regions keep following blocks in their container after patches and save', async ({ page }) => {
  const errors = []
  page.on('pageerror', error => errors.push(error.message))
  page.on('console', message => {
    if (message.type() === 'error') errors.push(message.text())
  })

  await createModule(page, 'Nested regions', `
    <article data-liquid-test="nested">
      {% ref refs.heading %}{{ caption }}
      {% if true %}<div>{% if true %}<span>hidden if</span>{% endif %}</div>{% endif %}
      {% for row in rows %}<div>{% for col in row.cols %}<span>hidden loop</span>{% endfor %}</div>{% endfor %}
      {% unless false %}<div>{% unless false %}<span>hidden unless</span>{% endunless %}</div>{% endunless %}
      {% hide %}<div>{% hide %}<span>hidden hide</span>{% endhide %}</div>{% endhide %}
    </article>
  `)
  await createModule(page, 'Following block', '<article data-liquid-test="following">{% ref refs.heading %}{{ caption }}</article>')

  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill('Nested Liquid regions')
  await page.getByLabel('URI', { exact: true }).fill('nested-liquid-regions')
  await addModule(page, 'Nested regions')
  await addModule(page, 'Following block')

  const blocks = page.locator('#block-field-blocks > .entry-block')
  const nested = blocks.filter({ has: page.locator('[data-liquid-test="nested"]') })
  const following = blocks.filter({ has: page.locator('[data-liquid-test="following"]') })
  const assertStructure = async () => {
    await expect(blocks).toHaveCount(2)
    await expect(nested).toHaveCount(1)
    await expect(following).toHaveCount(1)
    await expect(nested.locator('.entry-block')).toHaveCount(0)
    await expect(following.locator('.entry-block')).toHaveCount(0)
    await expect(page.locator('.block-liquex-preview > .alert[role="alert"]')).toHaveCount(0)
    await expect(nested.locator('.block-liquex-preview')).not.toContainText('hidden')
    await expect(page.locator('#block-field-blocks')).not.toContainText(/\{%\s*end(?:if|for|unless|hide)/)
  }

  await assertStructure()
  await nested.locator('.header-block textarea').fill('Nested heading edited')
  await awaitBlockDebounce(page)
  await nested.getByLabel('Caption', { exact: true }).fill('Nested caption edited')
  await awaitBlockDebounce(page)
  await following.locator('.header-block textarea').fill('Following heading edited')
  await awaitBlockDebounce(page)
  await following.getByLabel('Caption', { exact: true }).fill('Following caption edited')
  await awaitBlockDebounce(page)
  await assertStructure()

  await page.getByTestId('submit').click()
  await expect(page).toHaveURL(/\/admin\/pages$/)
  await page.getByRole('link', { name: 'Nested Liquid regions', exact: true }).click()
  await syncLV(page)
  await assertStructure()
  await expect(nested.locator('.header-block textarea')).toHaveValue('Nested heading edited')
  await expect(following.locator('.header-block textarea')).toHaveValue('Following heading edited')
  await expect(nested.getByLabel('Caption', { exact: true })).toHaveValue('Nested caption edited')
  await expect(following.getByLabel('Caption', { exact: true })).toHaveValue('Following caption edited')
  await expect(nested.locator('.rendered-variable')).toHaveText('Nested caption edited')
  await expect(following.locator('.rendered-variable')).toHaveText('Following caption edited')
  expect(errors.filter(message => /stream container|phx-update|LiveView/i.test(message))).toEqual([])
})

test('a malformed template keeps unsaved ref controls editable', async ({ page }, testInfo) => {
  await createModule(page, 'Incomplete region', '<article>{% ref refs.heading %}{% if true %}<div>unfinished')
  await page.goto('/admin/pages/create')
  await syncLV(page)
  await page.getByLabel('Title', { exact: true }).fill('Incomplete Liquid region')
  await page.getByLabel('URI', { exact: true }).fill('incomplete-liquid-region')
  await addModule(page, 'Incomplete region')

  const block = page.locator('#block-field-blocks > .entry-block')
  const preview = block.locator('.block-liquex-preview')
  await expect(preview.locator(':scope > .alert[role="alert"]')).toContainText('The module preview is unavailable')
  await expect(preview.locator('article')).toHaveCount(0)
  await expect(preview.locator('.header-block textarea')).toHaveValue('Original heading')
  await preview.locator('.header-block textarea').fill('Keep this unsaved heading')
  await awaitBlockDebounce(page)
  await block.getByLabel('Caption', { exact: true }).fill('Trigger another patch')
  await awaitBlockDebounce(page)
  await expect(preview.locator('.header-block textarea')).toHaveValue('Keep this unsaved heading')
  await expect(block).toHaveCount(1)

  await page.setViewportSize({ width: 1440, height: 1000 })
  await block.screenshot({ path: testInfo.outputPath('liquid-preview-error-desktop.png') })
  await page.setViewportSize({ width: 390, height: 844 })
  await block.screenshot({ path: testInfo.outputPath('liquid-preview-error-mobile.png') })
})
