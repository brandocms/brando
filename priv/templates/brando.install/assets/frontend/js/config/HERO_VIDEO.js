import { TweenLite, Sine } from '@univers-agency/jupiter'

export default () => ({
  onFadeIn: hero => {
    TweenLite.to(hero.el, 1, {
      opacity: 1,
      delay: 0.5,
      ease: Sine.easeIn
    })
  }
})
