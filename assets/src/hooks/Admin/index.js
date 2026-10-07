import tippy from 'tippy.js'
import { Dom } from '@brandocms/jupiter'
import { alertError, alertWarning, alertInfo } from '../../alerts'

// Smoothly scrolls the window so `node` sits `offsetY` below where it would
// (a negative offset leaves room above it). The browser's own smooth scroll,
// not Jupiter's `app.scrollTo`: Jupiter animates with a requestAnimationFrame
// loop nothing can stop, so a scroll started just before a LiveView navigation
// went on dragging the next page down. On a new entry it pulled the status
// control out of view just after it was clicked, and its menu closed again.
// A native smooth scroll ends when the navigation scrolls to the top.
function scrollToNode(node, offsetY = 0) {
  const top = node.getBoundingClientRect().top + window.scrollY + offsetY
  const reduceMotion =
    document.querySelector('meta[name="prefers_reduced_motion"]') ||
    window.matchMedia('(prefers-reduced-motion: reduce)').matches
  window.scrollTo({ top: Math.max(top, 0), behavior: reduceMotion ? 'instant' : 'smooth' })
}

export default app => ({
  mounted() {
    console.log('==> Brando/Admin mounted.')

    // Shortcut labels read "Ctrl+S" instead of "⌘S" off a Mac.
    const mac = /mac|iphone|ipad/i.test(navigator.userAgentData?.platform || navigator.platform || navigator.userAgent)
    document.documentElement.classList.toggle('not-mac', !mac)

    setTimeout(() => {
      window.dispatchEvent(new CustomEvent('b:navigation:refresh_active'))
    }, 1)

    this.handleEvent('b:alert', ({ title, message, type }) => {
      if (type === 'error') {
        alertError(title, message)
      } else if (type === 'warning') {
        alertWarning(title, message)
      } else if (type === 'info') {
        alertInfo(title, message)
      } else {
        alertInfo(title, message)
      }
    })

    // watch navigation scroll
    const $navigation = Dom.find('#navigation')
    if ($navigation) {
      // stash scroll top
      $navigation.addEventListener('scroll', e => {
        // consider debouncing
        localStorage.setItem('stickyNavScrollTop', $navigation.scrollTop)
      })

      // restore scroll top
      let scrollTop = localStorage.getItem('stickyNavScrollTop')
      if (scrollTop) {
        $navigation.scrollTop = scrollTop
      }
    }

    this.handleEvent('b:open_window', ({ url }) => {
      console.log('==> Open window standalone')
      // open url in new tab/window
      window.open(url, '_blank')
    })

    this.handleEvent('b:scroll_to_first_error', () => {
      const $fieldErrors = Dom.all('.field-error')
      if (!$fieldErrors.length) return

      const firstError = $fieldErrors[0]
      // A negative offset stops short of the field and leaves it clear of
      // the top edge.
      scrollToNode(firstError, -50)

      // Scrolling alone leaves a keyboard or screen-reader user wherever they
      // were — usually the submit button — with no indication of which field
      // is wrong. Put the caret in the offending control instead; its
      // `aria-describedby` points back at this message, so it is read out on
      // arrival. The wait lets the scroll settle first, otherwise focus()
      // fights it with its own jump.
      const wrapper = firstError.closest('.field-wrapper')
      const control = wrapper && wrapper.querySelector('[aria-invalid="true"]')
      if (!control) return

      // The save error arrives as a modal alert (b:alert, pushed just before
      // this). While it is open the form is inert and focus() does nothing, and
      // closing it hands focus back to the submit button — so land in the field
      // when it closes instead.
      const alert = document.querySelector('dialog.admin-dialog[open]')
      if (alert) {
        alert.addEventListener('close', () => control.focus({ preventScroll: true }), { once: true })
      } else {
        setTimeout(() => control.focus({ preventScroll: true }), 300)
      }
    })

    this.handleEvent('b:scroll_to', ({ selector, focus }) => {
      // Cleared in destroyed(): a scroll asked for on the page we just left
      // must not move the next one.
      clearTimeout(this.scrollTimer)
      this.scrollTimer = setTimeout(() => {
        const $node = Dom.find(selector)
        if ($node) {
          scrollToNode($node, -50)
          if (focus) $node.focus({ preventScroll: true })
        }
      }, 250)
    })

    this.tippys = []
    this.initializeTippy()
  },

  disconnected() {
    app.disconnected = true
    app.reconnected = false
    console.log('==> socket disconnected')
    app.toast.connection(false, 'Mainframe connection was dropped. Attempting automatic reconnect...')
  },

  reconnected() {
    app.reconnected = true
    app.disconnected = false
    console.log('==> socket reconnected')
    app.toast.connection(true, 'Reconnected to mainframe!')
  },

  initializeTippy() {
    // tippy
    const $tippyEls = Dom.all(this.el, '[data-popover]')
    $tippyEls.forEach(el => {
      const content = el.dataset.popover
      this.tippys.push(tippy(el, { allowHTML: true, content }))
    })
  },

  destroyTippys() {
    this.tippys.forEach(t => t.destroy())
  },

  destroyed() {
    console.log('(!) Brando.Admin destroyed')
    clearTimeout(this.scrollTimer)
    this.destroyTippys()
  }
})
