import { Dom, gsap } from '@brandocms/jupiter'

function reset (app, el) {
  app.liveSocket.execJS(el, '[["add_class",{"names":["moonwalked"],"time":0,"to":null,"transition":[[],[],[]]}]]')
}

export default app => ({
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
        const toolsWrapper = Dom.find(el, '.list-tools-wrapper')
        const toolEls = Dom.all(el, '.list-tools .statuses > *, .list-tools .filters > *') || []
        const paginationEls = Dom.all(el, '.pagination > *')
        const listRows = Dom.all(el, '.list-row')
        let emptyList

        if (listRows.length) {
          gsap.set(listRows, { opacity: 0, x: -15 })
        } else {
          emptyList = Dom.find(el, '.empty-list')
          gsap.set(emptyList, { opacity: 0, y: 30 })
        }

        gsap.set(toolsWrapper, { opacity: 0 })
        gsap.set(toolEls, { opacity: 0, y: -15 })
        gsap.set(paginationEls, { opacity: 0, x: -15 })

        timeline
          .to(el, { opacity: 1, duration: 0.3, ease: 'none' })
          .to(toolsWrapper, { opacity: 1, duration: 0.3, ease: 'none' })
          .to(toolEls, { y: 0, duration: 0.3, ease: 'power3.out', stagger: 0.1 }, '<0.2')
          .to(toolEls, { opacity: 1, duration: 0.3, ease: 'none', stagger: 0.1 }, '<')
          
        if (listRows.length) {
          timeline
            .to(listRows, { x: 0, duration: 0.25, ease: 'power3.out', stagger: 0.06 }, '<0.2')
            .to(listRows, {
              opacity: 1, duration: 0.25, ease: 'none', stagger: 0.06, onComplete: () => {
                gsap.set(listRows, { clearProps: 'all' })
              }
            }, '<')
        } else {
          timeline
            .to(emptyList, { y: 0, ease: 'power3.out' })
            .to(emptyList, { opacity: 1, ease: 'none' }, '<')
        }

        timeline
          .to(paginationEls, { x: 0, duration: 0.25, ease: 'power3.out', stagger: 0.06 })
          .to(paginationEls, { opacity: 1, duration: 0.25, ease: 'none', stagger: 0.06 }, '<')

        timeline.call(() => {
          reset(app, el)
        })
      }
    },

    brandoForm: {
      threshold: 0.0,
      callback: el => {
        const timeline = gsap.timeline()
        const inputEls = Dom.all(el, '.form-tabs, .form-tabs button, .form-tabs .split-dropdown, .subform, .shaded, .brando-input')

        gsap.set(inputEls, { opacity: 0, x: -15 })

        timeline
          .to(el, { opacity: 1, duration: 0.25, ease: 'none' })
          .to(inputEls, { x: 0, duration: 0.25, ease: 'power3.out', stagger: 0.06 }, '<0.2')
          .to(inputEls, { opacity: 1, duration: 0.25, ease: 'none', stagger: 0.06 }, '<')
          .call(() => { gsap.set(inputEls, { clearProps: 'all' }) })
          .call(() => { reset(app, el) })
      }
    },

    brandoHeader: {
      threshold: 0.0,
      callback: el => {
        const timeline = gsap.timeline()
        const els = [
          Dom.find(el, 'h1'),
          Dom.find(el, 'h3'),
          Dom.find(el, '.actions')
        ]

        gsap.set(el, { scaleX: 0, transformOrigin: 'left', opacity: 1 })
        gsap.set(els, { opacity: 0, x: -15 })

        timeline
          .to(el, { delay: 0.5, scaleX: 1, ease: 'circ.in', duration: 0.25 })
          .to(els, { x: 0, duration: 0.25, ease: 'power3.out', stagger: 0.06 })
          .to(els, { opacity: 1, duration: 0.25, ease: 'none', stagger: 0.06 }, '<')

        timeline.call(() => {
          reset(app, el)
        })
      }
    }
  },

  walks: {
    default: {
      interval: 0.2, // was 0.03
      duration: 0.65,
      transition: null
    },

    upDly: {
      interval: 0.15,
      duration: 0.3,
      startDelay: 1,
      alphaTween: true,
      transition: {
        from: {
          y: 10
        },

        to: {
          ease: 'circ.out',
          y: 0
        }
      }
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
