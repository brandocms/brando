import { computePosition, flip, offset, shift } from '@floating-ui/dom'

// One tooltip for the whole admin: any element with `data-tooltip="text"`
// shows the text on pointer hover after a short delay, and at once on keyboard
// focus. The listeners are delegated from the document, installed once, so
// elements LiveView adds later work without a hook (unlike Tippy's
// `data-popover`, which binds on mount).
//
// The tooltip never names the element: an icon-only button keeps its
// visually hidden label as its accessible name. When the tooltip says
// something the name doesn't, it is linked with `aria-describedby` while it
// shows. `data-tooltip-placement` overrides the default `top`.
//
// Painted as a manual popover, so it sits in the top layer above modal
// dialogs and drawers, and it takes no pointer events.

const HOVER_DELAY = 400
// Moving straight from one tooltip to the next skips the delay
const SKIP_DELAY_WITHIN = 300

export default () => {
  let tip = null
  let trigger = null
  let timer = null
  let hiddenAt = 0
  let observer = null
  let describedBy = false
  // The element last pressed: its tooltip stays away until the pointer leaves
  let pressed = null

  const ensureTip = () => {
    if (tip) return tip
    tip = document.createElement('div')
    tip.id = 'brando-tooltip'
    tip.className = 'brando-tooltip'
    tip.setAttribute('role', 'tooltip')
    tip.setAttribute('popover', 'manual')
    document.body.appendChild(tip)
    return tip
  }

  const accessibleName = el =>
    (el.getAttribute('aria-label') || el.textContent || '').replace(/\s+/g, ' ').trim()

  const position = async () => {
    if (!trigger || !tip) return
    const placement = trigger.dataset.tooltipPlacement || 'top'
    const { x, y } = await computePosition(trigger, tip, {
      strategy: 'fixed',
      placement,
      middleware: [offset(6), flip(), shift({ padding: 8 })],
    })
    if (!trigger) return
    tip.style.setProperty('left', `${x}px`)
    tip.style.setProperty('top', `${y}px`)
  }

  const clearTimer = () => {
    clearTimeout(timer)
    timer = null
  }

  const hide = () => {
    clearTimer()
    if (!trigger) return
    if (describedBy) trigger.removeAttribute('aria-describedby')
    describedBy = false
    observer?.disconnect()
    observer = null
    trigger = null
    hiddenAt = Date.now()
    if (tip?.matches(':popover-open')) tip.hidePopover()
    tip?.classList.remove('is-visible')
  }

  const show = el => {
    clearTimer()
    const text = el.dataset.tooltip
    if (!text || !el.isConnected) return
    if (trigger && trigger !== el) hide()

    const node = ensureTip()
    node.textContent = text
    if (trigger !== el) {
      trigger = el
      // Text that adds to the name describes the element; text that repeats
      // it would be read twice.
      if (!el.hasAttribute('aria-describedby') && accessibleName(el) !== text) {
        el.setAttribute('aria-describedby', node.id)
        describedBy = true
      }
      // LiveView may remove the element, or patch it into another button,
      // while the tooltip shows. Watched only while a tooltip is open. A
      // focused button keeps a tooltip that follows its new text; under the
      // pointer, the layout may have moved, so the next hover shows it.
      observer = new MutationObserver(() => {
        if (!trigger) return
        const current = trigger.dataset.tooltip
        if (!trigger.isConnected || !current) return hide()
        if (node.textContent === current) return
        if (!trigger.matches(':focus-visible')) return hide()
        node.textContent = current
        position()
      })
      observer.observe(document.body, { childList: true, subtree: true })
      observer.observe(el, { attributes: true, attributeFilter: ['data-tooltip'] })
    }

    if (!node.matches(':popover-open')) node.showPopover()
    position().then(() => trigger === el && node.classList.add('is-visible'))
  }

  const tooltipTarget = event =>
    event.target instanceof Element ? event.target.closest('[data-tooltip]') : null

  document.addEventListener('pointerover', event => {
    if (event.pointerType === 'touch') return
    const el = tooltipTarget(event)
    if (!el || el === trigger || el === pressed) return
    clearTimer()
    if (trigger || Date.now() - hiddenAt < SKIP_DELAY_WITHIN) return show(el)
    timer = setTimeout(() => show(el), HOVER_DELAY)
  })

  document.addEventListener('pointerout', event => {
    const el = tooltipTarget(event)
    if (!el) return
    // Still inside the same element (moving between its icon and label)
    if (event.relatedTarget instanceof Node && el.contains(event.relatedTarget)) return
    if (pressed === el) pressed = null
    clearTimer()
    // Keyboard focus keeps its tooltip
    if (trigger === el && !el.matches(':focus-visible')) hide()
  })

  document.addEventListener('pointerdown', event => {
    const el = tooltipTarget(event)
    pressed = el
    hide()
  })

  document.addEventListener('focusin', event => {
    const el = tooltipTarget(event)
    if (el && el === event.target && el.matches(':focus-visible')) show(el)
  })

  document.addEventListener('focusout', event => {
    if (trigger && event.target === trigger) hide()
  })

  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && trigger) hide()
  }, true)

  // Scrolling moves the element away from where its tooltip points
  document.addEventListener('scroll', () => trigger && hide(), { capture: true, passive: true })
  window.addEventListener('resize', () => trigger && hide(), { passive: true })
  // A LiveView navigation replaces the page under the tooltip
  window.addEventListener('phx:page-loading-start', hide)
}
