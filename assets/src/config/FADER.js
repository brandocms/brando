import { gsap } from '@brandocms/jupiter'

export default () => ({
  fadeIn: callback => {
    gsap.to('.fader', {
      opacity: 0,
      duration: 0.25,
      delay: 0,
      ease: 'none',
      onComplete: () => {
        gsap.set('.fader', { display: 'none' })
        document.body.classList.remove('unloaded')
        callback()
      }
    })
  }
})
