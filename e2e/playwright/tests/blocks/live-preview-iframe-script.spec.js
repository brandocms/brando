import { test, expect } from '@playwright/test'
import path from 'path'

// The script inside the live preview iframe (`priv/static/js/livepreview.js`),
// loaded into a blank page with a stub Phoenix channel so each server push can
// be fired directly. No server or fixtures involved.
const JS = path.join(__dirname, '../../../../priv/static/js')

const load = async (page, bodyHtml) => {
  const errors = []
  page.on('pageerror', (error) => errors.push(error.message))
  await page.setContent(
    `<html><head><meta name="user_token" content="t"></head><body>${bodyHtml}</body></html>`
  )
  await page.evaluate(() => {
    window.livePreviewKey = 'test'
    window.__lp = { handlers: {}, patched: [] }
    const receipt = { receive: () => receipt }
    window.Phoenix = {
      Socket: class {
        connect() {}
        channel() {
          return {
            on: (event, fn) => (window.__lp.handlers[event] = fn),
            onError() {},
            onClose() {},
            join: () => receipt,
          }
        }
      },
    }
    document.addEventListener('brando:livepreview:patched', ({ detail }) => {
      window.__lp.patched.push({
        type: detail.type,
        uid: detail.uid,
        elements: detail.elements.map((el) => el.tagName),
      })
    })
  })
  await page.addScriptTag({ path: path.join(JS, 'morphdom-umd.min.js') })
  await page.addScriptTag({ path: path.join(JS, 'livepreview.js') })
  return errors
}

const push = (page, event, payload) =>
  page.evaluate(([event, payload]) => window.__lp.handlers[event](payload), [event, payload])

const patched = (page) => page.evaluate(() => window.__lp.patched)

test.describe('Live preview iframe script', () => {
  test('a block update keeps a leading <style> and announces the block', async ({ page }) => {
    const errors = await load(page, '<main><!-- [+:B<a>] --><div class="old">A</div><!-- [-:B<a>] --></main>')

    await push(page, 'update_block', {
      uid: 'a',
      rendered_html: '<style>.x { color: rgb(255, 0, 0) }</style><div class="x">B</div>',
      has_children: false,
    })

    await expect(page.locator('main > style')).toHaveCount(1)
    await expect(page.locator('main > div.x')).toHaveText('B')
    await expect(page.locator('main > div.x')).toHaveCSS('color', 'rgb(255, 0, 0)')
    await expect(page.locator('main > div.old')).toHaveCount(0)
    expect(await patched(page)).toEqual([{ type: 'block', uid: 'a', elements: ['STYLE', 'DIV'] }])
    expect(errors).toEqual([])
  })

  test('a block whose element changes tag keeps updating', async ({ page }) => {
    const errors = await load(page, '<main><!-- [+:B<a>] --><div>one</div><!-- [-:B<a>] --></main>')

    await push(page, 'update_block', { uid: 'a', rendered_html: '<section>two</section>', has_children: false })
    await push(page, 'update_block', { uid: 'a', rendered_html: '<section>three</section>', has_children: false })

    await expect(page.locator('main > section')).toHaveText('three')
    await expect(page.locator('main > div')).toHaveCount(0)
    expect((await patched(page)).map((p) => p.elements)).toEqual([['SECTION'], ['SECTION']])
    expect(errors).toEqual([])
  })

  test('entry updates and full rerenders announce what they patched', async ({ page }) => {
    const errors = await load(page, '<header>Site</header><main><p>old</p></main>')

    await push(page, 'update', { html: '<main><p>new</p></main>' })
    await expect(page.locator('main p')).toHaveText('new')

    await push(page, 'rerender', { html: '<html><body><header>Site</header><main><p>again</p></main></body></html>' })
    await expect(page.locator('main p')).toHaveText('again')

    expect(await patched(page)).toEqual([
      { type: 'update', elements: ['MAIN'] },
      { type: 'rerender', elements: ['BODY'] },
    ])
    expect(errors).toEqual([])
  })

  test('an entry update patches the body when the template has no <main>', async ({ page }) => {
    const errors = await load(page, '<div id="app">old</div>')

    await push(page, 'update', { html: '<html><body><div id="app">new</div></body></html>' })

    await expect(page.locator('#app')).toHaveText('new')
    expect(errors).toEqual([])
  })

  test('entry updates still land after a rerender replaced <main>', async ({ page }) => {
    const errors = await load(page, '<main id="before"><p>old</p></main>')

    // A different id makes morphdom replace the element rather than patch it.
    await push(page, 'rerender', { html: '<html><body><main id="after"><p>rerendered</p></main></body></html>' })
    await push(page, 'update', { html: '<main id="after"><p>typed</p></main>' })

    await expect(page.locator('main p')).toHaveText('typed')
    expect(errors).toEqual([])
  })
})
