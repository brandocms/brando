import { prefersReducedMotion } from '../motion'

export default () => ({
  fadeIn: callback => {
    let revealed = false
    let fallback
    const onConnected = ({ detail }) => {
      if (detail.kind === 'initial') hide()
    }
    const hide = () => {
      if (revealed) return
      revealed = true
      clearTimeout(fallback)
      clearTimeout(window.bfTO)
      window.removeEventListener('phx:page-loading-stop', onConnected)
      window.removeEventListener('brando:login-revealing', hide)
      const reduced = prefersReducedMotion()
      const alreadyVisible = document.documentElement.classList.contains('app-revealed')
      if (!document.getElementById('application-login') && !reduced && !alreadyVisible) {
        document.getElementById('navigation')?.animate([
          { opacity: 0, transform: 'translateX(-32px)' },
          { opacity: 1, transform: 'translateX(0)' },
        ], { duration: 550, delay: 50, fill: 'backwards', easing: 'cubic-bezier(0.22, 1, 0.36, 1)' })
        document.getElementById('admin')?.animate([{ opacity: 0 }, { opacity: 1 }],
          { duration: 450, delay: 170, fill: 'backwards', easing: 'ease-out' })
      }
      // The first paint is guarded by the root layout's CSS. Lift that guard
      // only after all entrance animations have their hidden first frames.
      document.documentElement.classList.add('app-revealed')
      document.querySelectorAll('.fader').forEach(cover => {
        cover.style.pointerEvents = 'none'
        const done = () => { cover.style.display = 'none' }
        if (reduced) done()
        else cover.animate([{ opacity: 1 }, { opacity: 0 }], { duration: 220, easing: 'ease-out' }).finished.then(done)
      })
      document.body.classList.remove('unloaded')
      callback()
    }

    if (document.getElementById('application-login')) {
      window.addEventListener('brando:login-revealing', hide, { once: true })
      fallback = setTimeout(hide, 2000)
    } else if (document.getElementById('entry-skeleton')) {
      hide()
    } else {
      // The disconnected dashboard has no content yet. Reveal the shell
      // together with its first connected render, with an offline fallback.
      window.addEventListener('phx:page-loading-stop', onConnected)
      fallback = setTimeout(hide, 800)
    }
  }
})
