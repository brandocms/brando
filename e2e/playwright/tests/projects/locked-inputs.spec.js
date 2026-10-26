import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A top-level input declared `readonly: true` or `disabled: true` is locked:
// a save ignores what the browser sends for it, so it must not look or act
// editable. Text inputs render `readonly` (still readable and selectable);
// every other control sits in an inert field base. The fixtures are the
// `:locked` forms of E2eProject.Projects.InlineRow and Project, which declare
// one input of each type locked.

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', { data: { schema, attributes, creator_id: 1, fields: ['id'] } })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

// The locked field whose label is `label`, exactly
const lockedField = (page, label) =>
  page.locator('.field-wrapper[data-locked]').filter({
    has: page.locator(':scope > .label-wrapper .control-label > span:first-child', { hasText: new RegExp(`^${label}$`) }),
  })

// Clicks the middle of `locator` with the mouse, past Playwright's checks
// that the element takes events: an inert control doesn't, which is the claim.
async function clickThrough(page, locator) {
  const box = await locator.boundingBox()
  expect(box).not.toBeNull()
  await page.mouse.click(box.x + box.width / 2, box.y + box.height / 2)
  await syncLV(page)
}

async function expectLocked(field) {
  await expect(field).toHaveCount(1)
  await expect(field.locator(':scope > .label-wrapper .field-lock [data-icon]')).toBeVisible()
}

// Typing into a read-only input changes nothing
async function expectReadonlyText(page, field, value) {
  await expectLocked(field)
  const input = field.locator('input.text, textarea.text').first()
  await expect(input).toHaveAttribute('readonly', '')
  await expect(input).toHaveValue(value)
  await input.click()
  await page.keyboard.type('changed')
  await expect(input).toHaveValue(value)
  await expect(field.locator(':scope > .field-base')).not.toHaveAttribute('inert')
}

async function expectInert(field) {
  await expectLocked(field)
  await expect(field.locator(':scope > .field-base')).toHaveAttribute('inert', '')
}

test('every locked input type renders locked and takes no edit', async ({ page }) => {
  const row = await factory(page, 'E2eProject.Projects.InlineRow', {
    title: 'Opening night',
    status: 'published',
    key: '<p>{{ entry.title }}</p>',
    notes: 'Doors at seven.',
    email: 'hello@example.com',
    phone: '+47 22 00 00 00',
    amount: 120,
    starts_on: '2026-11-14',
    starts_at: '2026-11-14T19:00:00Z',
    color: '#254e3f',
    kind: 'talk',
    size: 'm',
    featured: true,
    confirmed: true,
    aliases: ['Premiere'],
    tags: ['red'],
    label: { en: 'Opening', no: 'Åpning' },
    description: { en: 'The first night.', no: 'Første kveld.' },
  })

  await page.goto(`/admin/projects/inline_rows/locked/${row.id}`)
  await syncLV(page)

  // Text inputs, `readonly: true` and `disabled: true` alike
  await expectReadonlyText(page, lockedField(page, 'Title'), 'Opening night')
  await expectReadonlyText(page, lockedField(page, 'Notes'), 'Doors at seven.')
  await expectReadonlyText(page, lockedField(page, 'Email'), 'hello@example.com')
  await expectReadonlyText(page, lockedField(page, 'Phone'), '+47 22 00 00 00')
  await expectReadonlyText(page, lockedField(page, 'Amount'), '120')
  await expectReadonlyText(page, lockedField(page, 'Label'), 'Opening')
  await expectReadonlyText(page, lockedField(page, 'Description'), 'The first night.')

  // A translated input's other languages can still be read
  const label = lockedField(page, 'Label')
  await label.getByRole('tab', { name: 'no', exact: true }).click()
  await expect(label.locator('input[lang="no"]')).toBeVisible()
  await expect(label.locator('input[lang="no"]')).toHaveValue('Åpning')

  // Every other control is inert: a click reaches nothing
  for (const name of ['Status', 'Key', 'Date', 'Date and time', 'Colour', 'Kind', 'Size', 'Featured', 'Confirmed', 'Aliases', 'Tags', 'Image', 'File', 'Video']) {
    await expectInert(lockedField(page, name))
  }

  const status = lockedField(page, 'Status')
  await clickThrough(page, status.locator('.status-label.draft'))
  await expect(status.locator('input[value="published"]')).toBeChecked()

  // Neither the control nor the field's label, which is outside the inert
  // part, flips a toggle or a checkbox
  const featured = lockedField(page, 'Featured')
  await clickThrough(page, featured.locator('.slider'))
  await featured.locator(':scope > .label-wrapper .control-label').click()
  await syncLV(page)
  await expect(featured.locator('input[type="checkbox"]')).toBeChecked()

  const confirmed = lockedField(page, 'Confirmed')
  await clickThrough(page, confirmed.locator('.check-wrapper'))
  await confirmed.locator(':scope > .label-wrapper .control-label').click()
  await syncLV(page)
  await expect(confirmed.locator('input[type="checkbox"]')).toBeChecked()

  const size = lockedField(page, 'Size')
  await clickThrough(page, size.locator('input[value="l"]'))
  await expect(size.locator('input[value="m"]')).toBeChecked()

  // The select's and the date picker's dialogs don't open
  const kind = lockedField(page, 'Kind')
  await clickThrough(page, kind.getByRole('button').first())
  await expect(page.getByRole('dialog')).toHaveCount(0)

  await clickThrough(page, lockedField(page, 'Date').locator('input:not([type="hidden"])').first())
  await expect(page.locator('.flatpickr-calendar.open')).toHaveCount(0)

  // A string list's empty row takes no focus, so nothing can be typed into
  // it; a media field opens no file chooser
  const aliases = lockedField(page, 'Aliases')
  await clickThrough(page, aliases.locator('.string-list-add input'))
  await expect(aliases.locator(':focus')).toHaveCount(0)
  await expect(aliases.locator('input.string-list-input')).toHaveCount(2)

  let chooserOpened = false
  page.on('filechooser', () => (chooserOpened = true))
  await clickThrough(page, lockedField(page, 'Image').getByRole('button').first())
  expect(chooserOpened).toBe(false)
})

test('locked rich text, selects, multi-select, gallery and entries take no edit', async ({ page }) => {
  const client = await factory(page, 'E2eProject.Projects.Client', {
    name: 'Fjord', slug: 'fjord-locked', status: 'published', language: 'en',
  })
  const project = await factory(page, 'E2eProject.Projects.Project', {
    title: 'Locked project', slug: 'locked-project', status: 'published', language: 'en',
    introduction: '<p>The introduction.</p>', full_case: true, client_id: client.id,
  })

  await page.goto(`/admin/projects/projects/locked/${project.id}`)
  await syncLV(page)

  await expectReadonlyText(page, lockedField(page, 'Title'), 'Locked project')

  // Rich text stays text: no toolbar, and the editor doesn't open for typing
  const introduction = lockedField(page, 'Introduction')
  await expectLocked(introduction)
  await expect(introduction.locator('[data-tiptap-readonly="true"]')).toHaveCount(1)
  await expect(introduction.locator('.tiptap-menu')).toBeHidden()
  // A click doesn't open the editor (keys typed now would reach the page's
  // shortcuts, not a field)
  await introduction.locator('.tiptap-wrapper').click()
  await syncLV(page)
  await expect(introduction.locator('[contenteditable="true"]')).toHaveCount(0)
  await expect(introduction.locator('.tiptap-wrapper')).toContainText('The introduction.')

  for (const name of ['Full case', 'Categories', 'Client', 'Project gallery', 'Related entries']) {
    await expectInert(lockedField(page, name))
  }

  await clickThrough(page, lockedField(page, 'Client').getByRole('button').first())
  await expect(page.getByRole('dialog')).toHaveCount(0)

  await clickThrough(page, lockedField(page, 'Related entries').getByRole('button').first())
  await expect(page.getByRole('dialog')).toHaveCount(0)
})
