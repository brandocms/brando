// Follow mode: click another editor's avatar to keep their work in view.
//
// It uses the presence events the form already receives — the block and field
// another editor moves to (`b:set_active_block`) and the entry field they
// focus (`b:set_active_field`) — and scrolls there. It stops when this editor
// scrolls, presses a key or clicks anywhere else, or clicks the avatar or the
// bar's × again.
//
// The avatars are server-rendered buttons; their pressed state is a sticky
// attribute (`hook.js()`), so patches keep it. The bar sits in a
// `phx-update="ignore"` container: its label and visibility are this
// module's.

const SCROLL_KEYS = new Set(['ArrowUp', 'ArrowDown', 'PageUp', 'PageDown', 'Home', 'End', ' '])

export default function follow(hook) {
  let following = null
  // userId -> the element they were last seen in, to jump to at once
  const lastSeen = new Map()
  // our own smooth scroll fires scroll-ish events too; only the user's input stops follow mode
  let removeStopListeners = () => {}

  const bar = () => hook.el.querySelector('.follow-bar')
  const avatar = userId => hook.el.querySelector(`.page-presences [data-follow-user="${CSS.escape(String(userId))}"]`)

  const showBar = name => {
    const el = bar()
    if (!el) return
    el.querySelector('.follow-bar-label').textContent = (el.dataset.label || '%{name}').replace('%{name}', name)
    el.hidden = false
  }

  const hideBar = () => {
    const el = bar()
    if (el) el.hidden = true
  }

  const reveal = el => {
    if (!el || !document.contains(el)) return
    el.scrollIntoView({ block: 'center', behavior: 'smooth' })
  }

  const stop = () => {
    if (following === null) return
    const el = avatar(following)
    if (el) hook.js().setAttribute(el, 'aria-pressed', 'false')
    following = null
    hideBar()
    removeStopListeners()
  }

  const start = userId => {
    stop()
    const el = avatar(userId)
    if (!el) return
    following = String(userId)
    hook.js().setAttribute(el, 'aria-pressed', 'true')
    showBar(el.dataset.presenceName || '')
    reveal(lastSeen.get(following))

    // Registered after this click has finished propagating, so the click
    // that started following does not stop it.
    setTimeout(() => {
      if (following !== String(userId)) return
      const onPointer = event => {
        if (event.target.closest('[data-follow-user], .follow-bar')) return
        stop()
      }
      const onKey = event => {
        if (SCROLL_KEYS.has(event.key) || event.target.closest?.('input, textarea, [contenteditable]')) stop()
      }
      window.addEventListener('wheel', stop, { passive: true })
      window.addEventListener('touchmove', stop, { passive: true })
      window.addEventListener('pointerdown', onPointer, true)
      window.addEventListener('keydown', onKey, true)
      removeStopListeners = () => {
        window.removeEventListener('wheel', stop)
        window.removeEventListener('touchmove', stop)
        window.removeEventListener('pointerdown', onPointer, true)
        window.removeEventListener('keydown', onKey, true)
        removeStopListeners = () => {}
      }
    }, 0)
  }

  const onClick = event => {
    const button = event.target.closest('[data-follow-user]')
    if (button && hook.el.contains(button)) {
      const userId = button.dataset.followUser
      following === userId ? stop() : start(userId)
      return
    }
    if (event.target.closest('.follow-bar-stop')) stop()
  }

  hook.el.addEventListener('click', onClick)

  return {
    // Another editor moved to `el`.
    seen(userId, el) {
      if (!el) return
      lastSeen.set(String(userId), el)
      if (following === String(userId)) reveal(el)
    },

    left(userId) {
      lastSeen.delete(String(userId))
      if (following === String(userId)) stop()
    },

    following: () => following,

    destroy() {
      stop()
      hook.el.removeEventListener('click', onClick)
    },
  }
}
