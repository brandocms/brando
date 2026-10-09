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
// dialogs and drawers, and it takes no pointer events. Without the Popover
// API it is a fixed element over the page (Tooltip.css).

const HOVER_DELAY = 400
// Moving straight from one tooltip to the next skips the delay
const SKIP_DELAY_WITHIN = 300

const supportsPopover = typeof HTMLElement !== 'undefined' &&
  typeof HTMLElement.prototype.showPopover === 'function'

let installed = false

export default () => {
  if (installed || document.getElementById('brando-tooltip')) return
  installed = true

  let tip = null
  let trigger = null
  // How the open tooltip was asked for: 'hover' or 'focus'
  let mode = null
  // The element whose hover delay is running
  let pending = null
  let timer = null
  let hiddenAt = 0
  let observer = null
  let frame = null
  let describedBy = false
  // The element last pressed: its tooltip stays away until the pointer leaves
  let pressed = null

  const ensureTip = () => {
    if (tip) return tip
    tip = document.createElement('div')
    tip.id = 'brando-tooltip'
    tip.className = 'brando-tooltip'
    tip.setAttribute('role', 'tooltip')
    if (supportsPopover) tip.setAttribute('popover', 'manual')
    else tip.hidden = true
    document.body.appendChild(tip)
    return tip
  }

  const isOpen = node => (supportsPopover ? node.matches(':popover-open') : !node.hidden)

  const open = node => {
    if (isOpen(node)) return
    if (supportsPopover) node.showPopover()
    else node.hidden = false
  }

  const close = node => {
    if (!isOpen(node)) return
    if (supportsPopover) node.hidePopover()
    else node.hidden = true
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

  // Once per frame, however many mutations or scroll events arrive
  const reposition = () => {
    if (frame) return
    frame = requestAnimationFrame(() => {
      frame = null
      position()
    })
  }

  const inViewport = el => {
    const r = el.getBoundingClientRect()
    return r.bottom > 0 && r.right > 0 && r.top < window.innerHeight && r.left < window.innerWidth
  }

  const clearTimer = () => {
    clearTimeout(timer)
    timer = null
    pending = null
  }

  // `fromHover`: the pointer left the element, so moving on to the next one
  // shows its tooltip at once.
  const hide = ({ fromHover = false } = {}) => {
    clearTimer()
    if (!trigger) return
    if (describedBy) trigger.removeAttribute('aria-describedby')
    describedBy = false
    observer?.disconnect()
    observer = null
    if (frame) cancelAnimationFrame(frame)
    frame = null
    trigger = null
    mode = null
    if (fromHover) hiddenAt = Date.now()
    if (tip) {
      close(tip)
      tip.classList.remove('is-visible')
    }
  }

  const show = (el, how) => {
    clearTimer()
    const text = el.dataset.tooltip
    if (!text || !el.isConnected) return
    if (trigger && trigger !== el) hide()

    const node = ensureTip()
    node.textContent = text
    mode = how
    if (trigger !== el) {
      trigger = el
      // Text that adds to the name describes the element; text the name
      // already says would be read twice.
      const name = accessibleName(el).toLowerCase()
      if (!el.hasAttribute('aria-describedby') && !name.includes(text.trim().toLowerCase())) {
        el.setAttribute('aria-describedby', node.id)
        describedBy = true
      }
      // LiveView may remove the element, move it, or patch it into another
      // button while the tooltip shows. Watched only while a tooltip is open.
      // A focused button keeps a tooltip that follows its new text; under the
      // pointer, the next hover shows it.
      observer = new MutationObserver(() => {
        if (!trigger) return
        const current = trigger.dataset.tooltip
        if (!trigger.isConnected || !current) return hide()
        if (node.textContent !== current) {
          if (mode !== 'focus') return hide()
          node.textContent = current
        }
        reposition()
      })
      observer.observe(document.body, { childList: true, subtree: true })
      observer.observe(el, { attributes: true, attributeFilter: ['data-tooltip'] })
    }

    open(node)
    position().then(() => trigger === el && node.classList.add('is-visible'))
  }

  const tooltipTarget = event =>
    event.target instanceof Element ? event.target.closest('[data-tooltip]') : null

  document.addEventListener('pointerover', event => {
    if (event.pointerType === 'touch') return
    // A button held down is a drag (Sortable, a selection): no tooltips
    if (event.buttons !== 0) return clearTimer()
    const el = tooltipTarget(event)
    // Moving over the icon or the label inside the same element
    if (!el || el === trigger || el === pending || el === pressed) return
    clearTimer()
    if ((trigger && mode === 'hover') || Date.now() - hiddenAt < SKIP_DELAY_WITHIN) return show(el, 'hover')
    pending = el
    timer = setTimeout(() => show(el, 'hover'), HOVER_DELAY)
  })

  document.addEventListener('pointerout', event => {
    const el = tooltipTarget(event)
    if (!el) return
    // Still inside the same element (moving between its icon and label)
    if (event.relatedTarget instanceof Node && el.contains(event.relatedTarget)) return
    if (pressed === el) pressed = null
    if (pending === el) clearTimer()
    // Keyboard focus keeps its tooltip
    if (trigger === el && mode === 'hover') hide({ fromHover: event.buttons === 0 })
  })

  document.addEventListener('pointerdown', event => {
    pressed = tooltipTarget(event)
    hide()
  })

  document.addEventListener('focusin', event => {
    const el = tooltipTarget(event)
    if (el && el === event.target && el.matches(':focus-visible')) show(el, 'focus')
  })

  document.addEventListener('focusout', event => {
    if (trigger && event.target === trigger) hide()
  })

  document.addEventListener('keydown', event => {
    if (event.key === 'Escape' && trigger) hide()
  }, true)

  // A hover tooltip goes when the page scrolls under it. Focus often scrolls
  // its element into view (Tab, a scrolling toolbar's arrow keys), so a focus
  // tooltip follows its element, until the element leaves the viewport.
  document.addEventListener('scroll', () => {
    if (!trigger) return
    if (mode === 'focus' && inViewport(trigger)) return reposition()
    hide()
  }, { capture: true, passive: true })
  window.addEventListener('resize', () => trigger && hide(), { passive: true })
  // A LiveView navigation replaces the page under the tooltip
  window.addEventListener('phx:page-loading-start', () => hide())
}
