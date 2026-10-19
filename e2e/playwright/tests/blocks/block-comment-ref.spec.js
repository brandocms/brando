import { test, expect } from '../../test-support/setupAuth'
import { syncLV } from '../../utils'

// A comment ref is a note to the editors, drawn in the editors' notes amber
// (--brando-note) rather than a content block's white, in a module of any
// colour: the module colours have ref rules of their own (Block.css).

async function factory(page, schema, attributes) {
  const response = await page.request.post('/__e2e/db/factory', {
    data: { schema, attributes, creator_id: 1, fields: ['id'] },
  })
  expect(response.ok(), await response.text()).toBeTruthy()
  return response.json()
}

for (const color of ['blue', 'pink']) {
  test(`a comment ref takes the note colours in a ${color} module`, async ({ page }) => {
    await factory(page, 'Brando.Content.Module', {
      name: { en: 'Editor note' },
      namespace: { en: 'Notes' },
      help_text: { en: 'A note' },
      class: 'editor-note',
      type: 'liquid',
      color,
      code: '<div>{% ref refs.note %}{% ref refs.body %}</div>',
      refs: [
        { name: 'note', description: 'Note', uid: 'comment-note', data: { type: 'comment', data: { text: 'Arranged under Works.' } } },
        { name: 'body', description: 'Text', uid: 'comment-body', data: { type: 'text', data: { text: '<p>Content</p>', extensions: ['p'], type: 'paragraph' } } },
      ],
      vars: [],
      multi: false,
      datasource: false,
    })
    const client = await factory(page, 'E2eProject.Projects.Client', {
      name: 'Note owner', slug: 'note-owner', status: 'published', language: 'en',
    })
    const project = await factory(page, 'E2eProject.Projects.Project', {
      title: 'Noted', slug: 'noted', client_id: client.id, introduction: '<p>Intro</p>', status: 'draft', language: 'en',
    })

    await page.setViewportSize({ width: 1440, height: 900 })
    await page.goto(`/admin/projects/projects/update/${project.id}`)
    await syncLV(page)
    await page.getByRole('button', { name: 'Add block', exact: true }).first().click()
    await page.getByRole('button', { name: /^Notes \d+$/ }).click()
    await page.getByRole('button', { name: 'Editor note', exact: true }).click()

    const comment = page.locator(".ref_block[data-block-type='comment']")
    await expect(comment).toContainText('Arranged under Works.')
    const token = name => page.evaluate(name => {
      const probe = document.createElement('div')
      probe.style.color = `var(${name})`
      document.body.append(probe)
      const value = getComputedStyle(probe).color
      probe.remove()
      return value
    }, name)
    const note = await token('--brando-note')
    await expect(comment).toHaveCSS('background-color', note)
    await expect(comment.locator('.block-content')).toHaveCSS('border-top-color', await token('--brando-note-line'))
    await expect(comment.locator('.block-actions .block-action').first()).toHaveCSS('color', await token('--brando-note-ink'))
    // The text block beside it keeps the white writing surface
    await expect(page.locator(".ref_block[data-block-type='text']")).not.toHaveCSS('background-color', note)
  })
}
