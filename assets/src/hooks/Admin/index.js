import tippy from 'tippy.js'
import { Dom, gsap } from '@brandocms/jupiter'
import { alertError, alertWarning, alertInfo } from '../../alerts'

export default app => ({
  mounted() {
    console.log('==> Brando/Admin mounted.')

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
      if ($fieldErrors.length) {
        const firstError = $fieldErrors[0]
        // const $tabWithError = firstError.closest('.form-tab')
        // console.log($tabWithError)
        // if (!Dom.hasClass($tabWithError, 'active')) {
        //   this.pushEvent
        //   console.log('has active!')
        // }
        app.scrollTo({ y: firstError, offsetY: 50 })
      }
    })

    this.handleEvent('b:scroll_to', ({ selector }) => {
      setTimeout(() => {
        const $node = Dom.find(selector)
        if ($node) {
          app.scrollTo({ y: $node, offsetY: 50 })
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
    app.toast.show({
      title: '⚡️',
      message: 'Mainframe connection was dropped. Attempting automatic reconnect...',
      theme: 'small-error',
      displayMode: 2,
      position: 'topRight',
      close: false,
      progressBar: false
    })
  },

  reconnected() {
    app.reconnected = true
    app.disconnected = false
    console.log('==> socket reconnected')
    app.toast.show({
      title: '✌️',
      message: 'Reconnected to mainframe!',
      theme: 'small-success',
      displayMode: 2,
      position: 'topRight',
      close: false,
      progressBar: false
    })
  },

  animateNav() {
    const targets = [
      Dom.find('#navigation-content header'),
      Dom.find('#navigation-content .current-user'),
      Dom.all('#navigation-content .navigation-section > *')
    ]
    gsap.to(targets, { duration: 0.35, x: 0, stagger: 0.02, ease: 'circ.out' })
    gsap.to(targets, { duration: 0.35, opacity: 1, stagger: 0.02, ease: 'none' })
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
    this.destroyTippys()
  }
})
