export default () => ({
  rootMargin: '0% 0% -10% 0%',
  threshold: 0,
  initialDelay: 100,

  walks: {
    default: {
      interval: 0.2, // was 0.03
      duration: 0.65,
      transition: null
    },

    panner: {
      interval: 0.2, // was 0.03
      duration: 0.65,
      transition: null
    },

    slide: {
      interval: 0.2, // was 0.03
      duration: 0.65,
      alphaTween: true,
      transition: null
    },

    fadeIn: {
      interval: 0,
      duration: 0.35,
      startDelay: 0,
      transition: {
        from: {
          scaleX: 0,
          transformOrigin: '0% 0%'
        },

        to: {
          scaleX: 1,
          ease: 'sine.out'
        }
      }
    }
  }
})
