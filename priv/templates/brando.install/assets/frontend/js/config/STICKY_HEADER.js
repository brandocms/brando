import {
  TimelineLite, TweenLite, Power3, Sine
} from '@univers-agency/jupiter'

export default application => ({
  el: 'header[data-nav]',
  default: {
    onMainVisible: h => {
      // ENSURE auxNav is getting hid
      h.unpin()

      const brandText = h.el.querySelector('.brand-text')
      const brandLogo = h.el.querySelector('.brand a')
      const contact = h.el.querySelector('.contact')

      const lis = [
        contact,
        brandText,
        h.el.querySelector('.line'),
        h.el.querySelectorAll('.primary li')
      ]

      const timeline = new TimelineLite()

      timeline
        .set(h.el, { opacity: 1 })
        .set(lis, { autoAlpha: 0 })
        .set(brandLogo, { y: 0, opacity: 0 })
        .staggerTo(lis, 0.3, { delay: 0.3, autoAlpha: 1, ease: Sine.easeIn }, 0.1)
        .to(brandLogo, 1.1, { y: 0, opacity: 1, ease: Power3.easeIn }, '-=0.8')
    },

    onMainInvisible: h => {
      TweenLite.to(
        h.el,
        1,
        { opacity: 0 },
      )
    },

    onSmall: h => {
      TweenLite.set(h.auxEl, { y: application.pxToHide * -1 })
    },

    onPin: h => {
      TweenLite.to(h.auxEl, 0.5, { autoAlpha: 1, yPercent: 0, ease: Sine.easeInOut })
    },

    onUnpin: h => {
      h._hiding = true
      TweenLite.to(
        h.auxEl,
        0.5,
        {
          autoAlpha: 0,
          yPercent: '-5',
          ease: Sine.easeInOut,
          autoRound: true,
          onComplete: () => {
            h._hiding = false
          }
        },
      )
    }
  }
})
