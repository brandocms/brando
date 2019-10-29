import { Sine, Expo } from '@univers-agency/jupiter'

export default () => ({
  rootMargin: '-10%',
  threshold: 0,

  walks: {
    default: {
      interval: 0.1, // was 0.03
      duration: 0.65,
      alphaTween: true,
      transition: {
        from: {
          y: 5
        },
        to: {
          // autoAlpha: 1,
          ease: Sine.easeOut,
          force3D: true,
          y: 0
        }
      }
    },

    fast: {
      duration: 0.2,
      interval: 0.07,
      transition: {
        from: {
          x: 8,
          autoAlpha: 0
        },

        to: {
          x: 0,
          autoAlpha: 1
        }
      }
    },

    slider: {
      sectionTargets: '.glide-slide',
      interval: 0.2,
      duration: 1.2,
      alphaTween: true,
      transition: {
        from: {
          autoAlpha: 0,
          y: 21
        },
        to: {
          ease: Sine.easeOut,
          y: 0
        }
      }
    }
  }
})
