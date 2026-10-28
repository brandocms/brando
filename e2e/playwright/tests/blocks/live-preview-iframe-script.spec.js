import { test, expect } from '@playwright/test'
import fs from 'fs'
import path from 'path'

// The script inside the live preview iframe (`priv/static/js/livepreview.js`)
// and the block patching it shares with frontend edit mode (`block_patch.js`),
// loaded into a blank page with a stub Phoenix channel so each server push can
// be fired directly. No server or fixtures involved.
const JS = path.join(__dirname, '../../../../priv/static/js')

const load = async (page, bodyHtml, version = 1, { script = true, maxAge = 900 } = {}) => {
  const errors = []
  page.on('pageerror', (error) => errors.push(error.message))
  await page.setContent(
    // The plug puts the meta at the end of the body, after the page's content
    `<html><head></head><body>${bodyHtml}<meta name="brando-live-preview" data-key="test" data-version="${version}" data-token="t" data-token-max-age="${maxAge}"></body></html>`
  )
  await page.evaluate(() => {
    window.__lp = { handlers: {}, patched: [] }
    // A join that succeeds, as the page's setup on join depends on it
    const receipt = { receive: (status, callback) => (status === 'ok' && callback(), receipt) }
    window.Phoenix = {
      Socket: class {
        constructor(path, opts) {
          window.__lp.socketPath = path
          window.__lp.socketParams = opts.params
        }
        connect() {}
        onError(fn) {
          window.__lp.socketError = fn
        }
        channel(topic, params) {
          window.__lp.topic = topic
          window.__lp.joinParams = params
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
  await page.addScriptTag({ path: path.join(JS, 'block_patch.js') })
  if (script) await page.addScriptTag({ path: path.join(JS, 'livepreview.js') })
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

  // Frontend edit mode replaces a whole block field between its markers.
  test('a field is replaced in place, keeping what surrounds it and unchanged blocks', async ({ page }) => {
    const errors = await load(
      page,
      `<main><h1 id="title">Title</h1><!-- [+:F<Page:1:blocks>] --><!-- [+:B<a>] --><p class="a">A</p><!-- [-:B<a>] --><!-- [+:B<b>] --><p class="b">B</p><!-- [-:B<b>] --><!-- [-:F<Page:1:blocks>] --><footer>Foot</footer></main>`
    )
    await page.evaluate(() => {
      window.__kept = document.querySelector('p.a')
      window.__title = document.getElementById('title')
    })

    const patchedParent = await page.evaluate(
      () =>
        window.BrandoBlockPatch.replaceField(
          'Page:1:blocks',
          '<!-- [+:B<a>] --><p class="a">A</p><!-- [-:B<a>] --><!-- [+:B<b>] --><p class="b">Changed</p><!-- [-:B<b>] -->'
        )?.tagName
    )

    expect(patchedParent).toBe('MAIN')
    await expect(page.locator('p.b')).toHaveText('Changed')
    await expect(page.locator('footer')).toHaveText('Foot')
    expect(await page.evaluate(() => document.querySelector('p.a') === window.__kept)).toBe(true)
    expect(await page.evaluate(() => document.getElementById('title') === window.__title)).toBe(true)
    expect(await page.evaluate(() => window.BrandoBlockPatch.findField('Page:1:blocks') !== null)).toBe(true)
    expect(await page.evaluate(() => window.BrandoBlockPatch.replaceField('Missing:1:blocks', '<p></p>'))).toBeNull()
    expect(errors).toEqual([])
  })
  // The page is sandboxed, with none of the viewer's cookies to fetch a token
  // with: the channel hands over fresh ones, and the socket connects with the
  // latest.
  test('the socket connects with the token the channel handed over last', async ({ page }) => {
    const errors = await load(page, '<main><p>old</p></main>')
    expect(await page.evaluate(() => window.__lp.socketPath)).toBe('/__livepreview/socket')
    expect(await page.evaluate(() => window.__lp.socketParams())).toEqual({ token: 't' })

    await push(page, 'token', { token: 'fresh' })
    expect(await page.evaluate(() => window.__lp.socketParams())).toEqual({ token: 'fresh' })

    // A refused connect with a token still fresh just tries again
    await page.evaluate(() => {
      window.fetch = async () => {
        window.__lp.probed = true
      }
      window.__lp.socketError()
    })
    expect(await page.evaluate(() => window.__lp.probed)).toBeUndefined()
    expect(errors).toEqual([])
  })

  // Away for longer than its token lasts, the socket has nothing to connect
  // with: the page loads again, for a fresh one, once the server answers. A
  // framed page asks the admin page framing it (a reload from inside would
  // send no cookies); a standalone window reloads itself.
  // (The framed page's request is in live-preview-sandbox.spec.js.)
  test('a connect refused after the token expired loads the page again', async ({ page }) => {
    // Within 30 seconds of its expiry, a token counts as expired
    const errors = await load(page, '<main><p>old</p></main>', 1, { maxAge: 30 })

    await page.evaluate(() => {
      window.fetch = async () => ({ type: 'opaque' })
    })
    const reloaded = page.waitForEvent('framenavigated')
    await page.evaluate(() => window.__lp.socketError())
    await reloaded
    expect(errors).toEqual([])
  })

  // The server does not answer: the page stays, and tries again on the next
  // refused connect
  test('an expired token does not reload the page while the server is away', async ({ page }) => {
    const errors = await load(page, '<main><p>old</p></main>', 1, { maxAge: 30 })
    let navigated = false
    page.on('framenavigated', () => (navigated = true))

    await page.evaluate(() => {
      window.__lp.probes = 0
      window.fetch = async () => {
        window.__lp.probes++
        throw new TypeError('Failed to fetch')
      }
      window.__lp.socketError()
    })
    await expect.poll(() => page.evaluate(() => window.__lp.probes)).toBe(1)
    await page.evaluate(() => window.__lp.socketError())
    await expect.poll(() => page.evaluate(() => window.__lp.probes)).toBe(2)
    await expect(page.locator('main p')).toHaveText('old')
    expect(navigated).toBe(false)
    expect(errors).toEqual([])
  })

  // The plug puts its meta right before the script, so the script reads that
  // one even when a look-alike comes later in the document.
  test('the page reads the meta right before its script', async ({ page }) => {
    const errors = await load(page, '<main><p>old</p></main>', 1, { script: false })
    const source = fs.readFileSync(path.join(JS, 'livepreview.js'), 'utf8')

    await page.evaluate((source) => {
      const own = document.createElement('meta')
      own.setAttribute('name', 'brando-live-preview')
      own.setAttribute('data-key', 'own')
      own.setAttribute('data-version', '1')
      own.setAttribute('data-token', 'own-token')
      const decoy = own.cloneNode()
      decoy.setAttribute('data-key', 'decoy')
      decoy.setAttribute('data-token', 'decoy-token')
      const script = document.createElement('script')
      script.textContent = source
      document.querySelector('meta[name="brando-live-preview"]').remove()
      document.body.append(own, decoy)
      document.body.insertBefore(script, decoy)
    }, source)

    expect(await page.evaluate(() => window.__lp.topic)).toBe('live_preview:own')
    expect(await page.evaluate(() => window.__lp.socketParams())).toEqual({ token: 'own-token' })
    expect(errors).toEqual([])
  })

  // Content in the page can hold a look-alike meta; the page keeps to the one
  // the plug put after it.
  test('the page takes its key and token from its own meta, not one in the content', async ({ page }) => {
    const errors = await load(
      page,
      '<main><meta name="brando-live-preview" data-key="other" data-version="9" data-token="planted"></main>'
    )

    expect(await page.evaluate(() => window.__lp.topic)).toBe('live_preview:test')
    expect(await page.evaluate(() => window.__lp.socketParams())).toEqual({ token: 't' })
    expect(errors).toEqual([])
  })

  // The channel replays the cache on join only when this version is not what
  // the page shows, so the page sends the one it was served, then the `v` of
  // each render it applies. With it go the block patches applied on top (each
  // patch's `p`), which the cache does not hold.
  test('the channel joins with the version the page shows and its patches', async ({ page }) => {
    const errors = await load(page, '<main><p>old</p></main>', 41)
    const join = () => page.evaluate(() => window.__lp.joinParams())

    expect(await join()).toEqual({ version: 41, patches: 0 })
    await push(page, 'update', { html: '<main><p>new</p></main>', v: 42 })
    expect(await join()).toEqual({ version: 42, patches: 0 })
    await push(page, 'update_block', { uid: 'x', rendered_html: '<p>x</p>', has_children: false, p: 1 })
    await push(page, 'update_block', { uid: 'x', rendered_html: '<p>y</p>', has_children: false, p: 2 })
    expect(await join()).toEqual({ version: 42, patches: 2 })
    await push(page, 'rerender', { html: '<html><body><main><p>again</p></main></body></html>', v: 43 })
    expect(await join()).toEqual({ version: 43, patches: 0 })
    await push(page, 'update_block', { uid: 'x', rendered_html: '<p>z</p>', has_children: false, p: 1 })
    await push(page, 'update', { html: '<main><p>newer</p></main>', v: 44 })
    expect(await join()).toEqual({ version: 44, patches: 0 })
    expect(errors).toEqual([])
  })

  // The page's lazy images carry what `initializeMedia` set and the server's
  // HTML does not, so compared naively they differ on every update: morphdom
  // would strip `srcset` and `data-ll-loaded` and `initializeMedia` put them back.
  test('an update leaves an unchanged lazy image alone and still applies changes to one', async ({ page }) => {
    const image = (alt) =>
      `<!-- [+:B<a>] --><figure><img data-ll-srcset-image data-src="/a.jpg" data-srcset="/a.jpg 1x" alt="${alt}"></figure><!-- [-:B<a>] -->`
    const errors = await load(page, `<main>${image('A')}<!-- [+:B<b>] --><p>old</p><!-- [-:B<b>] --></main>`)

    await page.evaluate(() => {
      window.BrandoBlockPatch.initializeMedia(document)
      window.__mutations = []
      new MutationObserver((records) => window.__mutations.push(...records.map((r) => r.attributeName))).observe(
        document.querySelector('img'),
        { attributes: true }
      )
    })

    await push(page, 'update', { html: `<main>${image('A')}<!-- [+:B<b>] --><p>new</p><!-- [-:B<b>] --></main>`, v: 2 })
    await expect(page.locator('main p')).toHaveText('new')
    expect(await page.evaluate(() => window.__mutations)).toEqual([])
    await expect(page.locator('img')).toHaveAttribute('srcset', '/a.jpg 1x')

    await push(page, 'update', { html: `<main>${image('B')}<!-- [+:B<b>] --><p>new</p><!-- [-:B<b>] --></main>`, v: 3 })
    await expect(page.locator('img')).toHaveAttribute('alt', 'B')
    expect(await page.evaluate(() => window.__mutations)).toEqual(['alt'])

    await push(page, 'update_block', {
      uid: 'a',
      rendered_html: '<figure><img data-ll-srcset-image data-src="/a.jpg" data-srcset="/a.jpg 1x" alt="B"><figcaption>C</figcaption></figure>',
      has_children: false,
    })
    await expect(page.locator('figcaption')).toHaveText('C')
    expect(await page.evaluate(() => window.__mutations)).toEqual(['alt'])
    expect(errors).toEqual([])
  })
  // A root rendered whole for a block that cannot render on its own: the
  // blocks inside it keep their elements and keep receiving their own patches.
  test('a root patched whole keeps the blocks inside it patchable', async ({ page }) => {
    const nested = (child, sibling) =>
      `<section><!-- [+:B<child>] --><p class="child">${child}</p><!-- [-:B<child>] --><!-- [+:B<sibling>] --><p class="sibling">${sibling}</p><!-- [-:B<sibling>] --></section>`
    const errors = await load(page, `<main><!-- [+:B<root>] -->${nested('one', 'two')}<!-- [-:B<root>] --></main>`)
    await page.evaluate(() => (window.__sibling = document.querySelector('p.sibling')))

    await push(page, 'update_block', { uid: 'root', rendered_html: nested('changed', 'two'), has_children: false })
    await expect(page.locator('p.child')).toHaveText('changed')
    expect(await page.evaluate(() => document.querySelector('p.sibling') === window.__sibling)).toBe(true)

    await push(page, 'update_block', { uid: 'sibling', rendered_html: '<p class="sibling">patched</p>', has_children: false })
    await expect(page.locator('p.sibling')).toHaveText('patched')
    await expect(page.locator('p.child')).toHaveText('changed')

    // A nested block whose element the root patch replaced (its tag changed)
    // is patched where it now is
    const replaced = `<section><!-- [+:B<child>] --><h2 class="child">heading</h2><!-- [-:B<child>] --><!-- [+:B<sibling>] --><p class="sibling">patched</p><!-- [-:B<sibling>] --></section>`
    await push(page, 'update_block', { uid: 'root', rendered_html: replaced, has_children: false })
    await push(page, 'update_block', { uid: 'child', rendered_html: '<h2 class="child">edited</h2>', has_children: false })
    await expect(page.locator('h2.child')).toHaveText('edited')
    await expect(page.locator('p.child')).toHaveCount(0)
    expect(errors).toEqual([])
  })
  // Frontend edit mode patches blocks into a page nobody keyed
  test('a root patched whole on an unkeyed page keeps the blocks inside it', async ({ page }) => {
    const nested = (child) =>
      `<section><!-- [+:B<child>] --><p class="child">${child}</p><!-- [-:B<child>] --><!-- [+:B<sibling>] --><p class="sibling">two</p><!-- [-:B<sibling>] --></section>`
    const errors = await load(page, '<main></main>')
    await page.evaluate((html) => {
      document.querySelector('main').innerHTML = html
      window.__sibling = document.querySelector('p.sibling')
      window.__registry = window.BrandoBlockPatch.buildRegistry()
    }, `<!-- [+:B<root>] -->${nested('one')}<!-- [-:B<root>] -->`)

    await page.evaluate(
      (html) => window.BrandoBlockPatch.patchBlock(window.__registry, { uid: 'root', rendered_html: html, has_children: false }),
      nested('changed')
    )

    await expect(page.locator('p.child')).toHaveText('changed')
    expect(await page.evaluate(() => document.querySelector('p.sibling') === window.__sibling)).toBe(true)
    expect(errors).toEqual([])
  })

  test('a lazy image keeps what loaded it: its own loader, or the block it is', async ({ page }) => {
    const errors = await load(
      page,
      '<main><!-- [+:B<a>] --><img class="own" src="/placeholder.gif" data-src="/real.jpg"><!-- [-:B<a>] --><!-- [+:B<b>] --><img class="lazy" data-ll-srcset-image data-src="/b.jpg" data-srcset="/b.jpg 1x"><!-- [-:B<b>] --></main>'
    )
    // The site's loader swapped the placeholder; the preview initialised the other
    await page.evaluate(() => {
      document.querySelector('img.own').src = '/real.jpg'
      window.BrandoBlockPatch.initializeMedia(document.querySelector('img.lazy'))
    })

    await push(page, 'update_block', { uid: 'a', rendered_html: '<img class="own" src="/placeholder.gif" data-src="/real.jpg">', has_children: false })
    await push(page, 'update_block', {
      uid: 'b',
      rendered_html: '<img class="lazy" data-ll-srcset-image data-src="/b.jpg" data-srcset="/b.jpg 1x">',
      has_children: false,
    })

    await expect(page.locator('img.own')).toHaveAttribute('src', '/real.jpg')
    await expect(page.locator('img.lazy')).toHaveAttribute('srcset', '/b.jpg 1x')
    expect(errors).toEqual([])
  })
})
