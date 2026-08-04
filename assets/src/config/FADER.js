import { gsap } from '@brandocms/jupiter'

// How long to keep covering if the login reveal never announces itself.
const LOGIN_REVEAL_TIMEOUT = 2000

export default () => ({
  fadeIn: callback => {
    const hide = () => {
      gsap.set('.fader', { display: 'none' })
      document.body.classList.remove('unloaded')
      callback()
    }

    // The login screen choreographs its own reveal, and that reveal waits for
    // LiveView to mount. Dropping the cover on the app's schedule would expose
    // the staged-but-unanimated form in the gap. Wait for the reveal to say it
    // is starting — with a timeout, so a login page that never gets there is
    // still eventually shown rather than sitting behind a white sheet.
    if (document.getElementById('application-login')) {
      window.addEventListener('brando:login-revealing', hide, { once: true })
      setTimeout(hide, LOGIN_REVEAL_TIMEOUT)
      return
    }

    hide()
  }
})
