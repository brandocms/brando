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

// Cache DOM references. `<main>` is looked up on every update instead: a full
// rerender may replace it, and a template need not have one.
const token = document.querySelector('meta[name="user_token"]').getAttribute('content')
const body = document.querySelector('body')
const parser = new DOMParser()

// Phoenix Socket connection
const previewSocket = new Phoenix.Socket('/admin/socket', {
  params: { token: token },
})
previewSocket.connect()

const channel = previewSocket.channel('live_preview:' + livePreviewKey)

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
channel.on('update_block', function ({ uid, rendered_html, has_children }) {
  insertOverrideStyles()

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

  // Both trees, before the morph — see `stampBlockKeys` in block_patch.js.
  BlockPatch.stampBlockKeys(document)
  BlockPatch.stampBlockKeys(doc)

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
  rerender(parser.parseFromString(payload.html, 'text/html'))
})

function rerender(doc) {
  insertOverrideStyles()
  document.documentElement.classList.add('is-updated-live-preview')

  const newBody = doc.querySelector('body')

  BlockPatch.stampBlockKeys(document)
  BlockPatch.stampBlockKeys(doc)

  morphdom(body, newBody, BlockPatch.MORPHDOM_CONFIG_FULL)

  BlockPatch.initializeMedia(document)
  BlockPatch.stampBlockKeys(document)
  rebuildContentBlockRegistry()

  body.classList.remove('unloaded')
  BlockPatch.announcePatch('rerender', [body])
}

/**
 * Handle a full iframe reload request.
 *
 * Used when a change introduces new media (a freshly selected video/gallery) whose
 * player must be mounted by the host frontend's JS boot. morphdom can swap the DOM
 * but never runs that boot, so we reload the iframe: it re-fetches the (already
 * refreshed) cached HTML for the same key and the frontend mounts the player —
 * exactly like opening the preview.
 */
channel.on('reload', function () {
  window.location.reload()
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
  })
  .receive('error', resp => {
    console.error('[LivePreview] Channel join error:', resp)
    showConnectionStatus(false)
  })
  .receive('timeout', () => {
    console.error('[LivePreview] Channel join timeout')
    showConnectionStatus(false)
  })