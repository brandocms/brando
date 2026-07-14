// Shared block-lock presence state.
//
// Lock state lives in this map; the DOM classes are just its projection.
// LiveView patches reset a block's class attribute to server truth, wiping
// imperatively added lock decorations — locks used to flicker off whenever
// a locked block re-rendered (e.g. when its owner's shipped edit applied on
// the receiver). The Form hook maintains the map from presence events; the
// Block hook re-asserts its own lock in updated() after every patch.

const PRESENCE_COLORS = [
  ['77, 144, 254', 'blue'],     // blue
  ['72, 199, 142', 'green'],    // green
  ['245, 166, 35', 'orange'],   // orange
  ['168, 85, 247', 'purple'],   // purple
  ['239, 68, 68', 'red'],       // red
  ['20, 184, 166', 'teal'],     // teal
]

export const blockLocks = new Map()

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

export function clearBlockPresence(el) {
  el.classList.remove('block-presence-active', 'block-locked')
  el.removeAttribute('data-block-presence-user')
  el.removeAttribute('data-presence-color-index')
  el.style.removeProperty('--presence-color')
  el.style.removeProperty('--presence-color-strong')
  const lockIcon = el.querySelector('.block-lock-icon')
  if (lockIcon) lockIcon.remove()
}

// Idempotent: locks + glows a block for a user.
export function applyBlockLock(uid, userId) {
  const colorIdx = getPresenceColorIndex(userId)
  const color = getPresenceColor(userId)

  const block = document.querySelector(`[data-block-uid="${uid}"] > .block`)
  if (!block) return

  block.classList.add('block-presence-active', 'block-locked')
  block.setAttribute('data-block-presence-user', userId)
  block.setAttribute('data-presence-color-index', colorIdx)
  block.style.setProperty('--presence-color', color)
  block.style.setProperty('--presence-color-strong', getPresenceColor(userId, 0.8))

  // Add lock icon to block description if not present
  if (!block.querySelector('.block-lock-icon')) {
    const desc = block.querySelector('.block-description')
    if (desc) {
      const lock = document.createElement('div')
      lock.className = 'block-lock-icon'
      lock.style.color = color
      lock.innerHTML = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" width="14" height="14"><path fill-rule="evenodd" d="M10 1a4.5 4.5 0 0 0-4.5 4.5V9H5a2 2 0 0 0-2 2v6a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-6a2 2 0 0 0-2-2h-.5V5.5A4.5 4.5 0 0 0 10 1Zm3 8V5.5a3 3 0 1 0-6 0V9h6Z" clip-rule="evenodd" /></svg>'
      desc.prepend(lock)
    }
  }
}

export function setBlockLock(uid, userId) {
  // one lock per user — clear their previous block first
  for (const [lockedUid, lockedUserId] of blockLocks) {
    if (String(lockedUserId) === String(userId)) blockLocks.delete(lockedUid)
  }
  document
    .querySelectorAll(`[data-block-presence-user="${userId}"]`)
    .forEach(clearBlockPresence)

  blockLocks.set(uid, userId)
  applyBlockLock(uid, userId)
}

export function clearBlockLock(uid, userId) {
  if (String(blockLocks.get(uid)) === String(userId)) {
    blockLocks.delete(uid)
  }

  const block = document.querySelector(`[data-block-uid="${uid}"] > .block`)
  if (block && block.getAttribute('data-block-presence-user') === String(userId)) {
    clearBlockPresence(block)
  }
}

export function clearUserBlockLocks(userId) {
  for (const [lockedUid, lockedUserId] of blockLocks) {
    if (String(lockedUserId) === String(userId)) blockLocks.delete(lockedUid)
  }
  document
    .querySelectorAll(`[data-block-presence-user="${userId}"]`)
    .forEach(clearBlockPresence)
}

// Re-assert a single block's lock (called from the Block hook's updated()
// after LiveView patched the element and reset its classes)
export function reassertBlockLock(uid) {
  if (blockLocks.has(uid)) {
    applyBlockLock(uid, blockLocks.get(uid))
  }
}
