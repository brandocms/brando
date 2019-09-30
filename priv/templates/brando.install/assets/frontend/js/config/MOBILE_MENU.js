import {
  TweenLite, Power3, TimelineLite, Sine
} from '@univers-agency/jupiter'

export default () => ({
  logoColor: '#ffffff',
  hamburgerColor: '#ffffff',
  contentSelector: 'section.primary',

  onResize: m => {
    if (document.body.classList.contains('open-menu')) {
      TweenLite.to(m.bg, 0.1, { height: window.innerHeight })
    }
  },

  openTween: m => {
    const timeline = new TimelineLite()

    m.hamburger.classList.toggle('is-active')
    document.body.classList.toggle('open-menu')

    timeline
      .timeScale(1.8)
      .set(m.lis, { autoAlpha: 0 })
      .set(m.bg, { display: 'block' })
      .fromTo(m.bg, 0.35, { x: '0%', opacity: 0, height: window.innerHeight }, { opacity: 1, ease: Sine.easeIn })
      .to(m.logo, 0.5, { opacity: 0, ease: Power3.easeOut }, '-=0.35')
      .to(m.hamburger, 0.5, { opacity: 0, ease: Power3.easeOut }, '-=0.35')
      .to(m.header, 0.55, { backgroundColor: 'transparent', ease: Power3.easeOut }, '-=0.35')
      .set(m.nav, { height: window.innerHeight })
      .call(() => {
        TweenLite.set(m.content, { display: 'block' })
        const distanceToTop = m.logo.getBoundingClientRect().bottom
        TweenLite.set(m.content, { y: (distanceToTop / 2) * -1 })
        TweenLite.set(m.hamburger, { className: '+=close' })
      })
      .set(m.logoPath, { fill: m.opts.logoColor })
      .set(m.hamburger, { borderColor: '#ffffff', color: '#ffffff' })
      .call(() => { m.hamburger.innerHTML = 'Lukk' })
      .staggerFromTo(m.lis, 1, { x: 20 }, { x: 0, autoAlpha: 1, ease: Power3.easeOut }, 0.05)
      .to(m.logo, 0.55, { opacity: 1, xPercent: 0, ease: Power3.ease }, '-=1.2')
      .to(m.hamburger, 0.55, { opacity: 1, xPercent: 0, ease: Power3.ease }, '-=1.2')
      .call(m._emitMobileMenuOpenEvent)
  },

  closeTween: m => {
    document.body.classList.toggle('open-menu')
    const timeline = new TimelineLite()

    timeline
      .timeScale(1.8)
      .call(() => { m.hamburger.classList.toggle('is-active') })
      .fromTo(m.logo, 0.5, { opacity: 1 }, { opacity: 0, ease: Power3.easeOut })
      .fromTo(m.hamburger, 0.5, { opacity: 1 }, { opacity: 0, ease: Power3.easeOut }, '-=0.4')
      .set(m.logoPath, { clearProps: 'fill' })
      .set(m.hamburger, { clearProps: 'color,borderColor' })
      .staggerTo(m.lis, 0.5, { opacity: 0, x: 20, ease: Power3.easeOut }, 0.04, '-=0.4')
      .set(m.nav, { clearProps: 'height' })
      .set(m.content, { display: 'none' })
      .call(() => {
        TweenLite.set(m.content, { y: 0 })
      })
      .call(() => {
        m.hamburger.innerHTML = 'Meny'
        TweenLite.set(m.hamburger, { className: '-=close' })
      })
      .to(m.bg, 1.25, { opacity: 0, ease: Sine.easeIn }, '-=0.3')
      .call(() => { m._emitMobileMenuClosedEvent() })
      .set(m.lis, { clearProps: 'opacity' })
      .to(m.logo, 0.35, { opacity: 1, ease: Power3.easeIn }, '-=0.8')
      .to(m.hamburger, 0.55, { opacity: 1, ease: Power3.easeIn }, '-=0.6')
      .set(m.bg, { display: 'none' })
  }
})
