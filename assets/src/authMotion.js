import { prefersReducedMotion } from './motion'

const EASE = 'cubic-bezier(0.22, 1, 0.36, 1)'
const EXIT_MS = 350

export default function installAuthMotion() {
  let revealedLogin
  let departures = []
  let pending
  let continuing
  let continuedEvent

  const reveal = () => {
    const login = document.getElementById('application-login')
    if (!login || login === revealedLogin) return
    revealedLogin = login
    // One compositor animation per element: no whole-screen fade ahead of
    // the box, and no separate x/opacity animation competing for its frames.
    if (!prefersReducedMotion() && !document.documentElement.classList.contains('login-revealed')) {
      const enter = (el, transform, duration, delay = 0) => el?.animate([
        { opacity: 0, transform },
        { opacity: 1, transform: 'none' },
      ], { duration, delay, easing: EASE, fill: 'backwards' })
      enter(login.querySelector('.login-box'), 'translateY(24px)', 650)
      enter(login.querySelector('.figure-wrapper'), 'translateX(-10px)', 500, 140)
      const rows = [...login.querySelectorAll('.login-form > form:not(.login-passkey-alternative) > :not(input), .login-form > :not(form), .login-passkey-alternative')]
        .filter(row => !row.hidden)
      rows.forEach((row, i) => enter(row, 'translateY(10px)', 450, 180 + Math.min(i, 6) * 55))
    }
    document.documentElement.classList.add('login-revealed')
    window.dispatchEvent(new CustomEvent('brando:login-revealing'))
  }

  window.addEventListener('brando:login-mounted', reveal)
  // Keep a disconnected login usable too.
  setTimeout(reveal, 1200)

  const beforeUnload = event => {
    // The editor may ask whether to leave with unsent changes. Restore its
    // visibility if that native prompt cancels navigation after our exit.
    if (event.defaultPrevented) reset()
  }
  const reset = () => {
    clearTimeout(pending)
    pending = null
    departures.forEach(animation => animation.cancel())
    departures = []
    window.removeEventListener('beforeunload', beforeUnload)
    document.documentElement.classList.remove('login-submitting', 'auth-leaving')
    document.getElementById('application-login')?.removeAttribute('aria-busy')
  }

  // Bubble after the form's own handlers, but before LiveView's window listener
  // tears down its sockets for native navigation. Resume with requestSubmit so validation,
  // the original submitter, CSRF and other submit listeners are all preserved.
  // The delay is fixed, before the request, and independent of credentials.
  document.addEventListener('submit', event => {
    const form = event.target
    if (form === continuing) {
      continuedEvent = event
      return
    }
    if (event.defaultPrevented || !form.hasAttribute('action') || form.hasAttribute('phx-submit') || form.hasAttribute('phx-change')) return
    const submitter = event.submitter
    const action = new URL(submitter?.hasAttribute('formaction') ? submitter.formAction : form.action)
    const method = submitter?.hasAttribute('formmethod') ? submitter.formMethod : form.method
    const login = form.closest('#application-login')
    const logout = action.pathname === '/admin/logout'
    if (action.origin !== window.location.origin || method !== 'post' ||
      !(logout || login && /^\/admin\/login(?:\/|$)/.test(action.pathname))) return
    if (prefersReducedMotion()) return
    event.preventDefault()
    if (pending) return
    reset()
    document.documentElement.classList.add('auth-leaving')
    if (login) {
      login.setAttribute('aria-busy', 'true')
      document.documentElement.classList.add('login-submitting')
    }
    const leave = (el, transform) => {
      if (!el) return
      const from = getComputedStyle(el)
      departures.push(el.animate([
        { opacity: from.opacity, transform: from.transform },
        { opacity: 0, transform },
      ], { duration: EXIT_MS, easing: 'cubic-bezier(0.4, 0, 0.2, 1)', fill: 'forwards' }))
    }
    if (login) leave(login.querySelector('.login-box'), 'translateY(-12px)')
    else {
      leave(document.getElementById('navigation'), 'translateX(-40px)')
      leave(document.getElementById('admin'), 'none')
      leave(document.getElementById('brando-chrome'), 'none')
    }
    pending = setTimeout(() => {
      pending = null
      if (!form.isConnected || submitter && !submitter.isConnected) return reset()
      continuing = form
      continuedEvent = null
      // Register after the editor's own beforeunload guard.
      window.addEventListener('beforeunload', beforeUnload, { once: true })
      try {
        form.requestSubmit(submitter || undefined)
      } finally {
        continuing = null
        // Validation or another handler can still stop the resumed submit.
        if (!continuedEvent || continuedEvent.defaultPrevented) reset()
      }
    }, EXIT_MS)
  })
  window.addEventListener('pageshow', event => {
    if (event.persisted) reset()
  })
  window.addEventListener('keydown', event => {
    if (event.key === 'Escape') reset()
  })
}
