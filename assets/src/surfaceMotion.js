import { motionDuration, prefersReducedMotion } from './motion'

// Dialog/drawer visibility belongs to LiveView's sticky attributes; only the
// temporary movement belongs to Web Animations. Unlike timed JS.show/hide
// commands, a new action can cancel the old exit without a late hide winning.
export default function surfaceMotion(liveSocket) {
  const running = new WeakMap()
  const js = liveSocket.js()

  return (el, kind, action) => {
    const previous = running.get(el)
    const visible = getComputedStyle(el).display !== 'none'
    const open = action === 'toggle' ? !(previous?.open ?? visible) : action === 'show'
    if (previous?.open === open) return previous.finished
    if (!previous && visible === open) return Promise.resolve()

    const panel = kind === 'modal' ? el.querySelector(':scope > .modal-dialog') : el
    const backdrop = kind === 'modal'
      ? el.querySelector(':scope > .modal-backdrop')
      : el.nextElementSibling?.matches('.media-drawer-backdrop') ? el.nextElementSibling : null
    const away = kind === 'modal' ? 'translateY(12px) scale(0.985)'
      : el.classList.contains('left')
        ? `translateX(calc(-100% - ${getComputedStyle(el).getPropertyValue('--drawer-left-offset') || '0px'}))`
        : 'translateX(100%)'

    // Capture the painted values before cancelling: reversing halfway through
    // a close should begin where the panel is, without jumping to either end.
    const parts = [panel, backdrop].filter(Boolean).map(part => {
      const style = getComputedStyle(part)
      const fade = kind === 'modal' || part === backdrop
      const move = part === panel
      const from = {
        ...(fade && { opacity: visible ? style.opacity : 0 }),
        ...(move && { transform: visible ? style.transform : away }),
      }
      const to = {
        ...(fade && { opacity: open ? 1 : 0 }),
        ...(move && { transform: open ? 'none' : away }),
      }
      return { part, from, to }
    })
    previous?.cancel()

    let finish
    const finished = new Promise(resolve => { finish = resolve })
    const animations = []
    let timer
    const settle = cancelled => {
      clearTimeout(timer)
      if (running.get(el) !== state) return
      if (!cancelled) {
        js.setAttribute(el, 'data-ui-open', String(open))
        el.dispatchEvent(new Event(open ? 'phx:show-end' : 'phx:hide-end'))
      }
      animations.forEach(animation => animation.cancel())
      running.delete(el)
      finish()
    }
    const state = { open, finished, cancel: () => settle(true) }
    running.set(el, state)

    if (kind === 'drawer') {
      document.querySelectorAll(`[aria-controls="${CSS.escape(el.id)}"][aria-expanded]`).forEach(trigger => {
        js.setAttribute(trigger, 'aria-expanded', String(open))
      })
    }

    // Keep the shell present throughout an exit, including server-gated
    // dialogs. The blocking dispatch is released only when the exit finishes.
    js.setAttribute(el, 'data-ui-open', 'true')
    el.dispatchEvent(new Event(open ? 'phx:show-start' : 'phx:hide-start'))
    const style = getComputedStyle(el)
    const duration = prefersReducedMotion() ? 0
      : motionDuration(el, open ? '--motion-enter' : '--motion-leave')
    if (!duration || !el.isConnected) {
      settle(false)
      return finished
    }

    const easing = style.getPropertyValue(open ? '--motion-ease' : '--motion-ease-close').trim() || 'ease'
    try {
      parts.forEach(({ part, from, to }) => {
        animations.push(part.animate([from, to], { duration, easing, fill: 'both' }))
      })
      Promise.all(animations.map(animation => animation.finished)).then(() => settle(false)).catch(() => {})
      // Background tabs can suspend animation completion. Never leave a
      // blocking LiveView dispatch unresolved when that happens.
      timer = setTimeout(() => settle(false), duration + 50)
    } catch {
      settle(false)
    }
    return finished
  }
}
