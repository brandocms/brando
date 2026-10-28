/**
 * Brando CMS Live Preview
 * 
 * This module handles real-time preview updates for the Brando CMS admin interface.
 * It connects to a Phoenix socket channel and updates the DOM efficiently using morphdom
 * when content changes are broadcast from the server.
 */

// Initialize live preview environment
document.documentElement.classList.add('is-live-preview')

// Block patching is shared with frontend edit mode (`block_patch.js`, loaded
// before this file).
const BlockPatch = window.BrandoBlockPatch

// What `Brando.Plug.LivePreview` served this page with: the preview key, the
// generation of the cached document, and a socket token good only for this
// preview's channel (`Brando.LivePreview.SocketToken`).
// `livePreviewKey` and `livePreviewVersion` stay globals, as they were when the
// plug set them in an inline script.
// The plug puts the meta right before this script; read that one, not a
// look-alike in the page's content.
const livePreviewMeta = (() => {
  const own = document.currentScript && document.currentScript.previousElementSibling
  if (own && own.matches('meta[name="brando-live-preview"]')) return own
  const metas = document.querySelectorAll('meta[name="brando-live-preview"]')
  return metas[metas.length - 1]
})()
var livePreviewKey = livePreviewMeta.getAttribute('data-key')
var livePreviewVersion = Number(livePreviewMeta.getAttribute('data-version'))
let token = livePreviewMeta.getAttribute('data-token')
const tokenMaxAge = Number(livePreviewMeta.getAttribute('data-token-max-age')) || 15 * 60
let tokenReceivedAt = Date.now()
const clientScriptUrl = document.currentScript && document.currentScript.src

// Cache DOM references. `<main>` is looked up on every update instead: a full
// rerender may replace it, and a template need not have one.
const body = document.querySelector('body')
const parser = new DOMParser()

// The page is sandboxed (`Brando.Plug.LivePreview`): its origin is opaque and
// it has none of the viewer's cookies. Its socket is the admin socket served
// at `/__livepreview/socket`, which takes origin `null` and a preview token
// alone (`BrandoAdmin.AdminSocket.preview_transport/0`); the token is read on
// every connect.
const previewSocket = new Phoenix.Socket('/__livepreview/socket', {
  params: () => ({ token }),
})

// The page loads again from the admin page that frames it, which sends the
// viewer's cookies with the request; a page reloading itself would be turned
// away without them. A standalone window reloads itself: a top-level reload
// keeps them.
const framed = window.parent !== window

function reloadPage() {
  if (framed) {
    window.parent.postMessage({ source: 'brando-live-preview', type: 'reload' }, location.origin)
  } else {
    window.location.reload()
  }
}

// The token lasts `tokenMaxAge` seconds and the socket checks it only as it
// connects; the channel hands over a fresh one well before it expires
// (`token`). A socket away for longer than that has only an expired token to
// connect with, so the page loads again for a fresh one, once the server
// answers.
let recovering = false
previewSocket.onError(() => {
  if (recovering || Date.now() - tokenReceivedAt < (tokenMaxAge - 30) * 1000) return
  recovering = true
  fetch(clientScriptUrl || location.href, { mode: 'no-cors', cache: 'no-store' })
    .then(reloadPage)
    .catch(() => {
      recovering = false
    })
})
previewSocket.connect()

// The generation of the cached document this page shows: the one it was
// served (`livePreviewVersion`), then the `v` of each render it applies. Sent
// on every join, so the channel replays the cache only when this page missed a
// render.
let shownVersion = livePreviewVersion
// Block patches applied on top of that generation (each patch's `p`). The cache
// holds none of them, so the channel has the form render the page again when
// this is behind.
let shownPatches = 0
const channel = previewSocket.channel('live_preview:' + livePreviewKey, () => ({
  version: shownVersion,
  patches: shownPatches,
}))

// State management
let isFirstUpdate = true
let contentBlockRegistry = new Map()

// CSS overrides for live preview to ensure visibility of animated elements
const MOONWALK_OVERRIDE_STYLES = `
  .is-live-preview [data-moonwalk],
  .is-live-preview [data-moonwalk-run],
  .is-live-preview [data-moonwalk-section],
  .is-live-preview [data-moonwalk-children] > *,
  .is-live-preview [b-section] {
    opacity: 1 !important;
    transform: none !important;
    visibility: visible !important;
  }
  .is-live-preview [data-smart-video][data-revealed] {
    opacity: 1 !important;
    visibility: visible !important;
  }
`

function rebuildContentBlockRegistry() {
  contentBlockRegistry = BlockPatch.buildRegistry()
}

/**
 * Insert animation override styles on first update
 */
function insertOverrideStyles() {
  if (isFirstUpdate) {
    const style = document.createElement('style')
    style.innerHTML = MOONWALK_OVERRIDE_STYLES
    document.head.appendChild(style)
    isFirstUpdate = false
  }
}

/**
 * Handle individual block updates
 */
channel.on('update_block', function ({ uid, rendered_html, has_children, p }) {
  insertOverrideStyles()
  if (typeof p === 'number') shownPatches = p

  // If not found, rebuild the registry and try again
  if (!contentBlockRegistry.has(uid)) {
    rebuildContentBlockRegistry()
  }

  const elements = BlockPatch.patchBlock(contentBlockRegistry, { uid, rendered_html, has_children })

  if (!elements) {
    console.warn(`[LivePreview] Block not found in registry: ${uid}`)
    return
  }

  // Handle empty content (removed blocks)
  if (rendered_html === '') {
    contentBlockRegistry.delete(uid)
  }

  BlockPatch.announcePatch('block', elements, uid)
})

/**
 * Handle full page updates (main content only)
 */
channel.on('update', function (payload) {
  document.documentElement.classList.add('is-updated-live-preview')
  shownVersion = payload.v
  shownPatches = 0

  const doc = parser.parseFromString(payload.html, 'text/html')
  const main = document.querySelector('main')
  const newMain = doc.querySelector('main')

  // Without a `<main>` on either side the server sent the whole document
  // (`Brando.LivePreview` only trims it to `<main>` when there is one), so
  // patch the body instead of throwing.
  if (!main || !newMain) {
    rerender(doc)
    return
  }

  // Both trees, before the morph — see `prepareMorph` in block_patch.js.
  BlockPatch.prepareMorph(document, doc)

  morphdom(main, newMain, BlockPatch.MORPHDOM_CONFIG_CHILDREN_ONLY)

  BlockPatch.initializeMedia(document)
  BlockPatch.stampBlockKeys(document)
  rebuildContentBlockRegistry()
  BlockPatch.announcePatch('update', [main])
})

/**
 * Handle full page re-renders (entire body)
 */
channel.on('rerender', function (payload) {
  shownVersion = payload.v
  shownPatches = 0
  rerender(parser.parseFromString(payload.html, 'text/html'))
})

function rerender(doc) {
  const newBody = doc.querySelector('body')

  BlockPatch.prepareMorph(document, doc)

  morphdom(body, newBody, BlockPatch.MORPHDOM_CONFIG_FULL)

  preparePage()
  BlockPatch.announcePatch('rerender', [body])
}

/**
 * Get the page ready for patching: media loaded and marked booted (a booted
 * video container is never morphed, so a player the site mounted survives),
 * animations shown, blocks keyed and registered.
 *
 * Runs once the channel is joined, and after every full rerender. The channel
 * used to replay the page it had just served on every join, and that morph is
 * what ran this on load.
 */
function preparePage() {
  insertOverrideStyles()
  document.documentElement.classList.add('is-updated-live-preview')
  BlockPatch.initializeMedia(document)
  BlockPatch.stampBlockKeys(document)
  rebuildContentBlockRegistry()
  body.classList.remove('unloaded')
}

/**
 * Handle a full iframe reload request.
 *
 * Used when a change introduces new media (a freshly selected video/gallery) whose
 * player must be mounted by the host frontend's JS boot. morphdom can swap the DOM
 * but never runs that boot, so we reload the iframe: it re-fetches the (already
 * refreshed) cached HTML for the same key and the frontend mounts the player —
 * exactly like opening the preview. See `reloadPage` for how.
 */
channel.on('reload', reloadPage)

/**
 * A fresh socket token for the next connect.
 */
channel.on('token', function (payload) {
  if (payload && payload.token) {
    token = payload.token
    tokenReceivedAt = Date.now()
  }
})

/**
 * Show or hide a connection status indicator
 * @param {boolean} connected - Whether the channel is connected
 */
function showConnectionStatus(connected) {
  let indicator = document.getElementById('lp-connection-status')
  if (connected) {
    if (indicator) indicator.remove()
    return
  }
  if (indicator) return
  indicator = document.createElement('div')
  indicator.id = 'lp-connection-status'
  indicator.textContent = 'Preview disconnected'
  indicator.style.cssText =
    'position:fixed;top:8px;right:8px;z-index:99999;padding:6px 14px;' +
    'background:#e53e3e;color:#fff;font:13px/1.4 sans-serif;border-radius:4px;' +
    'box-shadow:0 2px 6px rgba(0,0,0,.25);pointer-events:none;'
  document.body.appendChild(indicator)
}

// Channel lifecycle
channel.onError(() => showConnectionStatus(false))
channel.onClose(() => showConnectionStatus(false))

// Connect to the channel
channel
  .join()
  .receive('ok', () => {
    showConnectionStatus(true)
    preparePage()
  })
  .receive('error', resp => {
    console.error('[LivePreview] Channel join error:', resp)
    showConnectionStatus(false)
  })
  .receive('timeout', () => {
    console.error('[LivePreview] Channel join timeout')
    showConnectionStatus(false)
  })