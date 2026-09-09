import { autoUpdate, computePosition, flip, hide, offset, shift } from '@floating-ui/dom'

// Keep the menu in its LiveView/upload owner, but paint it in the browser's
// top layer so scrolling drawers, clipped refs and transformed blocks cannot
// cut it off. Native popovers also dismiss on outside clicks.
export default () => ({
  mounted() {
    this.trigger = this.el.querySelector('[popovertarget]')
    this.menu = this.el.querySelector('[popover]')
    this.onToggle = () => this.syncOpenState()
    this.onBeforeToggle = event => {
      if (event.newState === 'open') queueMicrotask(() => this.syncOpenState())
    }
    this.onClick = event => {
      if (this.menu.contains(event.target) && event.target.closest('button, a')) {
        // The next drawer/dialog should remember the visible opener, before
        // the action bubbles to LiveView or the UploadTrigger hook.
        this.close(true)
      }
    }
    this.onKeydown = event => {
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
    this.js().setAttribute(this.trigger, 'aria-expanded', String(open))
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
