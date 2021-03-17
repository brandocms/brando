import {
  Dom, gsap
} from '@brandocms/jupiter'

export default () => ({
  logoColor: '#000',
  logoPathSelector: 'svg path',
  contentSelector: 'section.main',
  hamburgerColor: '#000',

  onResize: m => {
    if (document.body.classList.contains('open-menu')) {
      gsap.set(m.bg, { height: window.innerHeight })
    }
  },

  openTween: m => {
    const timeline = gsap.timeline()
    const lines = Dom.all('.hamburger i')

    m.hamburger.classList.toggle('is-active')
    document.body.classList.toggle('open-menu')
    const inner = Dom.find(m.bg, '.inner')

    timeline
      .set(m.lis, {
        opacity: 0,
        x: 20
      })
      .set(inner, {
        opacity: 0,
        x: 0
      })
      .to(lines[1], { opacity: 0, duration: 0.3 })
      .to(lines[0], { y: 7, rotate: '45deg', transformOrigin: '50% 50%', duration: 0.3 }, '<')
      .to(lines[2], { y: -7, rotate: '-45deg', transformOrigin: '50% 50%', duration: 0.3 }, '<')
      .call(() => {
        gsap.to(m.header, { backgroundColor: 'transparent' })
      })
      .fromTo(m.bg, {
        duration: 0.35,
        x: '0%',
        opacity: 0,
        height: window.innerHeight
      }, {
        display: 'block',
        duration: 0.35,
        opacity: 1,
        ease: 'sine.in'
      })
      .to(inner, { opacity: 1, duration: 0.35 }, '-=0.35')
      .set(m.content, { display: 'block' })
      .to(m.lis, {
        duration: 1,
        x: 0,
        opacity: 1,
        ease: 'power3.out',
        stagger: 0.05
      })
      .call(m._emitMobileMenuOpenEvent)
  },

  closeTween: m => {
    const lines = Dom.all('.hamburger i')
    document.body.classList.toggle('open-menu')
    const timeline = gsap.timeline()
    const inner = Dom.find(m.bg, '.inner')

    timeline
      .call(() => { m.hamburger.classList.toggle('is-active') })
      .to(lines[1], { opacity: 1 })
      .to(lines[0], { y: 0, rotate: '0deg', transformOrigin: '50% 50%' }, '<')
      .to(lines[2], { y: 0, rotate: '0deg', transformOrigin: '50% 50%' }, '<')
      .to(m.lis, {
        duration: 0.5, opacity: 0, x: 20, ease: 'power3.out', stagger: 0.04
      }, '<')

      .to(inner, {
        duration: 0.25,
        x: '100%',
        ease: 'sine.in'
      }, '-=0.3')
      .to(m.bg, {
        duration: 0.25,
        opacity: 0,
        ease: 'sine.in'
      }, '-=0.2')
      .call(() => { m._emitMobileMenuClosedEvent() })
      .set(m.content, { display: 'none' })
      .set(m.lis, { clearProps: 'opacity' })
      .set(m.header, { clearProps: 'background-color' })
      .call(() => {
        m.app.header.update()
      })
  }
})
