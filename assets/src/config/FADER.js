import { gsap } from '@brandocms/jupiter'

export default () => ({
  fadeIn: callback => {
    gsap.set('.fader', { display: 'none' })
    document.body.classList.remove('unloaded')
    callback()
  }
})
