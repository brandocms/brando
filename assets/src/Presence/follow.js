// Follow mode: click another editor's avatar to keep their work in view.
//
// It uses the presence events the form already receives — the block and field
// another editor moves to (`b:set_active_block`) and the entry field they
// focus (`b:set_active_field`) — and scrolls there. It stops when this editor
// scrolls, presses a key or Escape, clicks anywhere else, or clicks the avatar
// or the chip's × again.
//
// While following, a frame in the followed editor's presence colour runs round
// the editing area (`#brando-main`), with a chip under the toolbar naming them
// (`follow_frame/1` in form.ex). The avatars' pressed state, the frame's and
// chip's `is-following` and their `data-presence-color-index` are sticky
// attributes (`hook.js()`), so patches keep them. The frame's place is
// measured into a stylesheet rule scoped to the form, not inline styles. The
// chip's name sits in a `phx-update="ignore"` span: it is this module's.

const SCROLL_KEYS = new Set(['ArrowUp', 'ArrowDown', 'PageUp', 'PageDown', 'Home', 'End', ' '])

export default function follow(hook) {
  let following = null
  // userId -> the element they were last seen in, to jump to at once
  const lastSeen = new Map()
  // our own smooth scroll fires scroll-ish events too; only the user's input stops follow mode
  let removeStopListeners = () => {}

  const frame = () => hook.el.querySelector('.follow-frame')
  const chip = () => hook.el.querySelector('.follow-chip')
  const avatar = userId => hook.el.querySelector(`.page-presences [data-follow-user="${CSS.escape(String(userId))}"]`)

  const style = document.createElement('style')
  document.head.appendChild(style)
  style.sheet.insertRule(`#${CSS.escape(hook.el.id)} {}`)
  const rule = style.sheet.cssRules[0].style
  const setProperty = (name, value) => {
    if (rule.getPropertyValue(name) !== value) rule.setProperty(name, value)
  }

  // The frame covers the editing area as it is on screen; the chip hangs
  // under the toolbar wherever the toolbar is (stuck or not yet).
  let placing = 0
  const place = () => {
    placing = 0
    const area = (document.getElementById('brando-main') || hook.el).getBoundingClientRect()
    const toolbar = hook.el.querySelector('.form-content > .form-tabs')
    const below = toolbar ? toolbar.getBoundingClientRect().bottom : 0
    setProperty('--follow-left', `${Math.max(0, area.left)}px`)
    setProperty('--follow-width', `${Math.min(window.innerWidth, area.right) - Math.max(0, area.left)}px`)
    setProperty('--follow-chip-top', `${Math.max(0, below) + 8}px`)
  }
  const schedulePlace = () => {
    if (!placing) placing = requestAnimationFrame(place)
  }

  const show = (userId, name) => {
    const js = hook.js()
    const color = avatar(userId)?.dataset.presenceColorIndex || '0'
    const label = chip()?.querySelector('.follow-chip-label')
    if (label) label.textContent = (label.dataset.label || '%{name}').replace('%{name}', name)
    place()
    ;[frame(), chip()].forEach(el => {
      if (!el) return
      js.setAttribute(el, 'data-presence-color-index', color)
      js.addClass(el, 'is-following')
    })
    window.addEventListener('scroll', schedulePlace, { passive: true })
    window.addEventListener('resize', schedulePlace, { passive: true })
  }

  const hide = () => {
    const js = hook.js()
    ;[frame(), chip()].forEach(el => {
      if (!el) return
      js.removeClass(el, 'is-following')
      js.removeAttribute(el, 'data-presence-color-index')
    })
    window.removeEventListener('scroll', schedulePlace)
    window.removeEventListener('resize', schedulePlace)
    if (placing) cancelAnimationFrame(placing)
    placing = 0
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
    hide()
    removeStopListeners()
  }

  const start = userId => {
    stop()
    const el = avatar(userId)
    if (!el) return
    following = String(userId)
    hook.js().setAttribute(el, 'aria-pressed', 'true')
    show(following, el.dataset.presenceName || '')
    reveal(lastSeen.get(following))

    // Registered after this click has finished propagating, so the click
    // that started following does not stop it.
    setTimeout(() => {
      if (following !== String(userId)) return
      const onPointer = event => {
        if (event.target.closest('[data-follow-user], .follow-chip')) return
        stop()
      }
      const onKey = event => {
        if (event.key === 'Escape' || SCROLL_KEYS.has(event.key) || event.target.closest?.('input, textarea, [contenteditable]')) stop()
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
    if (event.target.closest('.follow-chip-stop')) stop()
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
      style.remove()
    },
  }
}
