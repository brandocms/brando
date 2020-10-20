import { gsap } from '@univers-agency/jupiter'

export default () => ({
  onFadeIn: hero => {
    gsap.to(hero.el, {
      opacity: 1,
      delay: 0.5,
      ease: 'sine.in',
      duration: 1
    })
  }
})
