import { Dom, gsap } from '@brandocms/jupiter'
import { alertError } from '../../alerts'

export default (app) => ({
  mounted() {
    console.log('==> Brando/Admin mounted')
    this.animateNav()

    window.dispatchEvent(new CustomEvent('b:navigation:refresh_active'))

    this.handleEvent('b:alert', ({ title, message }) => {
      alertError(title, message)
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

    this.handleEvent('b:scroll_to', selector => {
      const $node = Dom.find(selector)
      if ($node) {
        app.scrollTo({ y: $node, offsetY: 50 })
      }
    })
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
    gsap.to(targets, { x: 0, stagger: 0.06, ease: 'circ.out' })
    gsap.to(targets, { opacity: 1, stagger: 0.06, ease: 'none' })
  },

  updated() {
    console.log('==> Brando.Admin updated')
  },

  destroyed() {
    console.log('(!) Brando.Admin destroyed')
  }
})