import { autoUpdate, computePosition, flip, hide, offset, shift } from '@floating-ui/dom'

const menus = [
  '.dropdown-content',
  '.simple-dropdown-content',
  '.status-dropdown',
  '.block-action-dropdown-content',
  '.block-field-dropdown-content',
  '.image-picker-action-dropdown',
  '.video-picker-action-dropdown',
  '.gallery-object-action-dropdown',
].join(', ')

export function positionDropdown(trigger, menu, { placement = 'bottom-end', onHidden } = {}) {
  const update = async () => {
    const { x, y, middlewareData } = await computePosition(trigger, menu, {
      strategy: 'fixed', placement,
      middleware: [offset(5), flip(), shift({ padding: 8 }), hide()],
    })
    if (!menu.matches(':popover-open')) return
    if (middlewareData.hide?.referenceHidden) return onHidden?.()
    // Existing menu styles have their own top/right rules, sometimes inside
    // deeply nested editor selectors. Position belongs to this layer alone.
    menu.style.setProperty('left', `${x}px`, 'important')
    menu.style.setProperty('top', `${y}px`, 'important')
  }
  return { update, stop: autoUpdate(trigger, menu, update) }
}

export function promoteDropdown(menu, js) {
  js.setAttribute(menu, 'data-floating-dropdown', '')
  js.setAttribute(menu, 'popover', 'manual')
  menu.showPopover()
}

// Keep the existing LiveView show/hide commands, action targets and delegated
// block handlers. Only the menu's painting/positioning moves to the top layer.
// Listening in capture also catches LiveView's non-bubbling transition events.
export default app => {
  const active = new Map()
  const js = app.liveSocket.js()

  const finish = menu => {
    const state = active.get(menu)
    if (!state) return
    state.position.stop()
    active.delete(menu)
    if (menu.matches(':popover-open')) menu.hidePopover()
    js.setAttribute(state.trigger, 'aria-expanded', 'false')
  }

  const close = (menu, restoreFocus = false) => {
    const state = active.get(menu)
    if (!state) return
    if (!menu.isConnected || !state.trigger.isConnected) return finish(menu)
    if (restoreFocus && menu.contains(document.activeElement)) state.trigger.focus({ preventScroll: true })
    js.hide(menu)
  }

  document.addEventListener('phx:show-start', event => {
    const menu = event.target
    if (!menu.matches(menus) || active.has(menu)) return
    const previous = menu.previousElementSibling
    const trigger = previous?.matches('button') ? previous : menu.parentElement
    active.forEach((_state, other) => close(other))
    promoteDropdown(menu, js)
    const placement = menu.classList.contains('status-dropdown')
      ? 'bottom-start'
      : menu.classList.contains('over') ? 'top-end' : 'bottom-end'
    const position = positionDropdown(trigger, menu, { placement, onHidden: () => close(menu) })
    active.set(menu, { trigger, position })
    js.setAttribute(trigger, 'aria-controls', menu.id)
  }, true)

  document.addEventListener('phx:show-end', event => {
    const state = active.get(event.target)
    if (!state) return
    // Compact status controls also set this in their existing command chain.
    // Reconcile after that chain, rather than toggling the attribute twice.
    js.setAttribute(state.trigger, 'aria-expanded', 'true')
    state.position.update()
  }, true)

  document.addEventListener('phx:hide-end', event => finish(event.target), true)

  // Registered after LiveView: let an option's click/change command run before
  // closing its menu. This includes radio labels and status command chains.
  window.addEventListener('click', event => {
    active.forEach(({ trigger }, menu) => {
      if (menu.contains(event.target)) {
        if (event.target.closest('button, a, label, input')) close(menu, true)
      } else if (!trigger.contains(event.target)) {
        close(menu)
      }
    })
  })

  document.addEventListener('keydown', event => {
    if (event.key !== 'Escape' || active.size === 0) return
    event.preventDefault()
    event.stopPropagation()
    active.forEach((_state, menu) => close(menu, true))
  }, true)

  document.addEventListener('phx:update', () => {
    active.forEach(({ trigger, position }, menu) => {
      if (!menu.isConnected || !trigger.isConnected) finish(menu)
      else position.update()
    })
  })
}
