// Shared block-lock presence helpers.
//
// Lock decorations go through LiveView's sticky JS commands (`hook.js()` —
// addClass/setAttribute et al funnel into DOM.putSticky), so the patcher
// itself re-applies them after every morphdom pass. No client-side lock
// store and no updated()-re-assert needed: DOM state IS the lock state.
// The presence color and the lock icon are pure CSS, keyed off the sticky
// `data-presence-color-index` attribute (inline styles and injected child
// nodes are not covered by the sticky mechanism).

const PRESENCE_COLORS = [
  ['77, 144, 254', 'blue'],     // blue
  ['72, 199, 142', 'green'],    // green
  ['245, 166, 35', 'orange'],   // orange
  ['168, 85, 247', 'purple'],   // purple
  ['239, 68, 68', 'red'],       // red
  ['20, 184, 166', 'teal'],     // teal
]

export function getPresenceColorIndex(userId) {
  const els = document.querySelectorAll('.page-presences [data-presence-user-id]')
  const ids = Array.from(els).map(el => el.dataset.presenceUserId)
  const idx = ids.indexOf(String(userId))
  return Math.max(0, idx) % PRESENCE_COLORS.length
}

export function getPresenceColor(userId, alpha = 0.6) {
  const [rgb] = PRESENCE_COLORS[getPresenceColorIndex(userId)]
  return `rgba(${rgb}, ${alpha})`
}

function lockEl(uid) {
  return document.querySelector(`[data-block-uid="${uid}"] > .block`)
}

function unlock(js, el) {
  js.removeClass(el, ['block-presence-active', 'block-locked'])
  js.removeAttribute(el, 'data-block-presence-user')
  js.removeAttribute(el, 'data-presence-color-index')
}

export function setBlockLock(js, uid, userId) {
  // one lock per user — clear their previous block first
  clearUserBlockLocks(js, userId)

  const block = lockEl(uid)
  if (!block) return

  js.addClass(block, ['block-presence-active', 'block-locked'])
  js.setAttribute(block, 'data-block-presence-user', String(userId))
  js.setAttribute(block, 'data-presence-color-index', String(getPresenceColorIndex(userId)))
}

export function clearBlockLock(js, uid, userId) {
  const block = lockEl(uid)
  if (block && block.getAttribute('data-block-presence-user') === String(userId)) {
    unlock(js, block)
  }
}

export function clearUserBlockLocks(js, userId) {
  document
    .querySelectorAll(`[data-block-presence-user="${userId}"]`)
    .forEach(el => unlock(js, el))
}
