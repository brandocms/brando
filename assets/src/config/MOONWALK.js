import { Dom, gsap } from '@brandocms/jupiter'

export default () => ({
  rootMargin: '0% 0% -10% 0%',
  threshold: 0,
  initialDelay: 100,

  runs: {
    brandoLogin: {
      threshold: 0.0,
      callback: el => {
        const timeline = gsap.timeline()
        gsap.set(['.field-wrapper', '.brando-versioning', '.login-box', '.primary', '.figure-wrapper', '.title'], { opacity: 0 })
        gsap.set('.login-box', { y: 35 })
        gsap.set(['.field-wrapper', '.primary', '.title'], { x: -15 })
        gsap.set('.figure-wrapper', { x: -10 })
        gsap.set('.brando-versioning', { xPercent: -200 })

        timeline
          .to(el, { opacity: 1, duration: 0.5, ease: 'none' })
          .to('.login-box', { y: 0, duration: 0.5, ease: 'power3.out' })
          .to('.login-box', { opacity: 1, duration: 0.5, ease: 'none' }, '<')
          .to(['.title', '.field-wrapper', '.primary'], { x: 0, duration: 0.35, ease: 'circ.out', stagger: 0.1 }, '<0.25')
          .to(['.title', '.field-wrapper', '.primary'], { opacity: 1, duration: 0.35, ease: 'none', stagger: 0.1 }, '<')
          .to('.figure-wrapper', { x: 0, duration: 0.35, ease: 'circ.out' }, '<')
          .to('.figure-wrapper', { opacity: 1, duration: 0.35, ease: 'none' }, '<')
          .to('.brando-versioning', { opacity: 1, ease: 'none' })
          .to('.brando-versioning', { xPercent: 0, ease: 'circ.out' })
      }
    },

    brandoList: {
      threshold: 0.0,
      callback: el => {
        const timeline = gsap.timeline()
        const toolEls = Dom.all(el, '.list-tools .statuses > *, .list-tools .filters > *') || []
        const listRows = Dom.all(el, '.list-row')
        const paginationEls = Dom.all(el, '.pagination > *')

        gsap.set(toolEls, { opacity: 0, y: -15 })
        gsap.set(listRows, { opacity: 0, x: -15 })
        gsap.set(paginationEls, { opacity: 0, x: -15 })

        timeline
          .to(el, { opacity: 1, duration: 0.5, ease: 'none' })
          .to(toolEls, { y: 0, duration: 0.5, ease: 'power3.out', stagger: 0.1 }, '<0.2')
          .to(toolEls, { opacity: 1, duration: 0.5, ease: 'none', stagger: 0.1 }, '<')
          .to(listRows, { x: 0, duration: 0.5, ease: 'power3.out', stagger: 0.06 }, '<0.2')
          .to(listRows, { opacity: 1, duration: 0.5, ease: 'none', stagger: 0.06, onComplete: () => {
            gsap.set(listRows, { clearProps: 'all' })
          } }, '<')
          .to(paginationEls, { x: 0, duration: 0.5, ease: 'power3.out', stagger: 0.06 })
          .to(paginationEls, { opacity: 1, duration: 0.5, ease: 'none', stagger: 0.06 }, '<')
      }
    },

    brandoForm: {
      threshold: 0.0,
      callback: el => {
        const timeline = gsap.timeline()
        const inputEls = Dom.all(el, '.form-tabs, .form-tabs button, .subform, .shaded, .brando-input')

        gsap.set(inputEls, { opacity: 0, x: -15 })

        timeline
          .to(el, { opacity: 1, duration: 0.5, ease: 'none' })
          .to(inputEls, { x: 0, duration: 0.5, ease: 'power3.out', stagger: 0.06 }, '<0.2')
          .to(inputEls, { opacity: 1, duration: 0.5, ease: 'none', stagger: 0.06 }, '<')
          .call(() => {
            gsap.set(inputEls, { clearProps: 'all' })
          })
      }
    },

    brandoHeader: {
      threshold: 0.0,
      callback: el => {
        const timeline = gsap.timeline()
        const els = [
          Dom.find(el, 'h1'),
          Dom.find(el, 'h3'),
          Dom.find(el, '.instructions')
        ]

        gsap.set(els, { opacity: 0, x: -15 })

        timeline
          .to(el, { opacity: 1, duration: 0.5, ease: 'none' })
          .to(els, { x: 0, duration: 0.5, ease: 'power3.out', stagger: 0.06 }, '<0.2')
          .to(els, { opacity: 1, duration: 0.5, ease: 'none', stagger: 0.06 }, '<')
      }
    }
  },

  walks: {
    default: {
      interval: 0.2, // was 0.03
      duration: 0.65,
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
