import { gsap, Dom } from '@brandocms/jupiter'

export default (app) => ({
  mounted () {
    this.$btns = Dom.all('button.namespace-button') 

    this.$btns.forEach(btn => {
      let content = btn.nextElementSibling
      console.log('content', content)
      gsap.set(content, { display: 'none' })

      btn.addEventListener('click', e => {
        e.stopPropagation()
        this.toggle(btn, content)
      })
    })
  },

  toggle(btn, content) {
    const open = Dom.hasClass(content, 'open')

    console.log('open', open)
    if (open) {
      Dom.removeClass(content, 'open')
      gsap.set(content, { display: 'none' })
    } else {
      gsap.set(content, { display: 'block' })
      Dom.addClass(content, 'open')
    }
  },

  openContent() {
    this.open = true
    this.$btn.classList.add('open')
    
    gsap.set(this.$content, { opacity: 0, x: -15, display: 'block' })
    const contentRect = this.$content.getBoundingClientRect()

    if (contentRect.height + buttonBottom > window.innerHeight) {
      gsap.set(this.$content, { top: (contentRect.height + 10) * -1 })
    }

    gsap.to(this.$content, { opacity: 1, x: 0, duration: '0.25' })
  },

  closeContent() {
    if (this.open) {
      this.open = false
      this.$btn.classList.remove('open')
      if (this.$content) {
        gsap.to(this.$content, {
          opacity: 0,
          x: -15,
          duration: '0.25',
          onComplete: () => {
            if (this.$content) {
              gsap.set(this.$content, { display: 'none' })
            }
          }
        })
      }
    }
  }
})