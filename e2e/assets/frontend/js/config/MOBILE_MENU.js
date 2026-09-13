import { animate, stagger } from '@brandocms/jupiter'

export default () => {
  let animation

  // A second click supersedes the previous animation and its completion callback.
  const play = async sequence => {
    animation?.stop()
    const current = animate(sequence)
    animation = current
    await current.finished
    return animation === current
  }

  return {
    logoColor: '#000',
    logoPathSelector: 'svg path',
    contentSelector: 'section.main',
    hamburgerColor: '#000',

    onResize: m => {
      if (document.body.classList.contains('open-menu')) {
        m.bg.style.height = `${window.innerHeight}px`
      }
    },

    openTween: async m => {
      const lines = m.hamburger.querySelectorAll('i')
      m.hamburger.classList.add('is-active')
      document.body.classList.add('open-menu')
      m.hamburger.setAttribute('aria-expanded', 'true')
      Object.assign(m.bg.style, {
        display: 'block',
        height: `${window.innerHeight}px`,
        transform: 'translateX(0)',
      })
      m.content.forEach(el => { el.style.display = 'block' })

      const finished = await play([
        [lines[1], { opacity: 0 }, { duration: 0.3, at: 0 }],
        [lines[0], { y: 7, rotate: 45 }, { duration: 0.3, at: 0 }],
        [lines[2], { y: -7, rotate: -45 }, { duration: 0.3, at: 0 }],
        [m.header, { backgroundColor: 'transparent' }, { duration: 0.3, at: 0 }],
        [m.bg, { opacity: [0, 1] }, { duration: 0.35, ease: 'easeIn', at: 0.3 }],
        [m.lis, { x: [20, 0], opacity: [0, 1] }, {
          duration: 1,
          ease: 'easeOut',
          delay: stagger(0.05),
          at: 0.3,
        }],
      ])

      if (finished) m._emitMobileMenuOpenEvent()
    },

    closeTween: async m => {
      const lines = m.hamburger.querySelectorAll('i')
      m.hamburger.classList.remove('is-active')
      document.body.classList.remove('open-menu')
      m.hamburger.setAttribute('aria-expanded', 'false')

      const finished = await play([
        [lines[1], { opacity: 1 }, { duration: 0.3, at: 0 }],
        [lines[0], { y: 0, rotate: 0 }, { duration: 0.3, at: 0 }],
        [lines[2], { y: 0, rotate: 0 }, { duration: 0.3, at: 0 }],
        [m.lis, { opacity: 0, x: 20 }, {
          duration: 0.5,
          ease: 'easeOut',
          delay: stagger(0.04),
          at: 0,
        }],
        [m.bg, { opacity: 0 }, { duration: 0.25, ease: 'easeIn', at: 0.3 }],
      ])

      if (!finished) return

      m.bg.style.display = 'none'
      m.content.forEach(el => { el.style.display = 'none' })
      m.lis.forEach(el => { el.style.removeProperty('opacity') })
      m.header.style.removeProperty('background-color')
      m.app.header.update()
      m._emitMobileMenuClosedEvent()
    },
  }
}
