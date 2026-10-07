import { autoUpdate, computePosition, flip, hide, offset, shift } from '@floating-ui/dom'

// Keep the menu in its LiveView/upload owner, but paint it in the browser's
// top layer so scrolling drawers, clipped refs and transformed blocks cannot
// cut it off. Native popovers also dismiss on outside clicks.
//
// A choice menu (`data-choice-menu`) holds radios instead of actions, like the
// entry's status: opening it focuses the chosen radio, arrow keys move the
// choice and keep the menu open, and a click or Enter chooses and closes.
export default () => ({
  mounted() {
    this.trigger = this.el.querySelector('[popovertarget]')
    this.menu = this.el.querySelector('[popover]')
    this.choiceMenu = this.el.hasAttribute('data-choice-menu')
    this.onToggle = () => this.syncOpenState()
    this.onBeforeToggle = event => {
      if (event.newState === 'open') queueMicrotask(() => this.syncOpenState())
    }
    this.onClick = event => {
      if (!this.menu.contains(event.target)) return
      if (event.target.closest('button, a')) {
        // The next drawer/dialog should remember the visible opener, before
        // the action bubbles to LiveView or the UploadTrigger hook.
        this.close(true)
      } else if (this.choiceMenu && event.detail > 0 && event.target.closest('label')) {
        // A click on a choice, also the one already chosen. The label still
        // checks its radio after this; arrow keys click with no detail.
        this.close(true)
      }
    }
    this.onKeydown = event => {
      if (
        this.choiceMenu && event.key === 'Enter' && this.isOpen() &&
        this.menu.contains(event.target) && event.target.matches('input')
      ) {
        // Enter in a radio would submit its form.
        event.preventDefault()
        this.close(true)
        return
      }
      if (event.key !== 'Escape' || !this.isOpen()) return
      event.preventDefault()
      event.stopPropagation()
      this.close(true)
    }
    this.onFocusOut = event => {
      if (event.relatedTarget && !this.el.contains(event.relatedTarget)) this.close()
    }
    this.menu.addEventListener('beforetoggle', this.onBeforeToggle)
    this.menu.addEventListener('toggle', this.onToggle)
    this.el.addEventListener('click', this.onClick)
    this.el.addEventListener('keydown', this.onKeydown)
    this.el.addEventListener('focusout', this.onFocusOut)
  },

  updated() {
    if (this.isOpen()) this.updatePosition()
  },

  destroyed() {
    this.stopPositioning?.()
    this.menu.removeEventListener('beforetoggle', this.onBeforeToggle)
    this.menu.removeEventListener('toggle', this.onToggle)
    this.el.removeEventListener('click', this.onClick)
    this.el.removeEventListener('keydown', this.onKeydown)
    this.el.removeEventListener('focusout', this.onFocusOut)
  },

  isOpen() {
    return this.menu.matches(':popover-open')
  },

  close(restoreFocus = false) {
    if (!this.isOpen()) return
    if (restoreFocus) this.trigger.focus({ preventScroll: true })
    this.menu.hidePopover()
    this.syncOpenState()
  },

  syncOpenState() {
    const open = this.isOpen()
    const opened = open && this.trigger.getAttribute('aria-expanded') !== 'true'
    this.js().setAttribute(this.trigger, 'aria-expanded', String(open))
    if (opened && this.choiceMenu) {
      const choice = this.menu.querySelector('input:checked:not(:disabled)') || this.menu.querySelector('input:not(:disabled)')
      choice?.focus({ preventScroll: true })
    }
    this.stopPositioning?.()
    this.stopPositioning = open
      ? autoUpdate(this.trigger, this.menu, () => this.updatePosition())
      : null
  },

  async updatePosition() {
    const { x, y, middlewareData } = await computePosition(this.trigger, this.menu, {
      strategy: 'fixed',
      placement: this.el.dataset.placement || 'bottom-start',
      middleware: [offset(5), flip(), shift({ padding: 8 }), hide()],
    })
    if (!this.isOpen()) return
    if (middlewareData.hide?.referenceHidden) return this.close()
    Object.assign(this.menu.style, { left: `${x}px`, top: `${y}px` })
  },
})
