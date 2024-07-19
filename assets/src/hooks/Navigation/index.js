import { Dom, gsap } from '@brandocms/jupiter'

export default app => ({
  mounted() {
    console.log('==> Navigation mounted.')
    const $navigation = Dom.find('#navigation')
    if (!$navigation) {
      return
    }
    this.setupNavCircle()
    this.setupNavDropdowns()
    this.setupCurrentUserDropdown()
  },

  setupCurrentUserDropdown() {
    this.$currentUserDropdown = document.querySelector('#current-user')
    this.$currentUserDropdownContent = Dom.find(this.$currentUserDropdown, '.dropdown-content')
    this.currentUserDropdownOpen = false
    this.$currentUserDropdown.addEventListener('click', e => {
      this.toggleCurrentUserDropdown()
    })
  },

  toggleCurrentUserDropdown() {
    const lis = this.$currentUserDropdownContent.querySelectorAll('li')

    gsap.to(this.$currentUserDropdown.querySelector('.dropdown-icon'), {
      duration: 0.35,
      rotate: '+=180'
    })
    if (this.currentUserDropdownOpen) {
      gsap.to(Array.from(lis).reverse(), { duration: 0.35, autoAlpha: 0, x: -8, stagger: 0.06 })
      gsap.to(this.$currentUserDropdown, { duration: 0.35, delay: 0.2, height: this.height })
      this.currentUserDropdownOpen = false
    } else {
      this.height = this.$currentUserDropdown.offsetHeight

      gsap.set(lis, { autoAlpha: 0, x: -8 })
      gsap.to(this.$currentUserDropdown, { duration: 0.35, height: 'auto' })
      gsap.to(lis, { duration: 0.35, delay: 0.2, autoAlpha: 1, x: 0, stagger: 0.06 })
      this.currentUserDropdownOpen = true
    }
  },

  toggleDropdown(trigger) {
    const dl = trigger.parentNode.parentNode
    const dd = dl.querySelector('dd')
    const lis = dd.querySelectorAll('li')

    if (trigger.classList.contains('open')) {
      gsap.to(Array.from(lis).reverse(), { duration: 0.35, autoAlpha: 0, x: -15, stagger: 0.03 })
      gsap.to(dl, { duration: 0.35, delay: 0.2, height: trigger.dataset.height })
      trigger.classList.remove('open')
    } else {
      trigger.dataset.height = dl.offsetHeight
      gsap.set(dl, { height: trigger.dataset.height })
      gsap.set(lis, { autoAlpha: 0, x: -15 })
      gsap.set(dd, { opacity: 1, display: 'block' })
      gsap.to(dl, { duration: 0.35, height: 'auto' })
      gsap.to(lis, { duration: 0.2, delay: 0.2, autoAlpha: 1, x: 0, stagger: 0.02 })
      trigger.classList.add('open')
    }
  },

  setupNavDropdowns() {
    const targets = [
      Dom.find('#navigation-content header'),
      Dom.find('#navigation-content .current-user'),
      Dom.all('#navigation-content .navigation-section > *')
    ]

    if (targets.filter(t => t !== null).length > 0) {
      // gsap.set(targets, { opacity: 0, x: -10 })
    }

    const dropdowns = document.querySelectorAll('nav [data-nav-expand]')

    console.log(dropdowns)

    dropdowns.forEach(dd => {
      dd.addEventListener('click', () => this.toggleDropdown(dd))
    })
  },

  setupNavCircle() {
    const circle = document.querySelector('.nav-circle')
    const dts = document.querySelectorAll('nav dl dt')
    dts.forEach(dt => {
      dt.addEventListener('mouseover', () => {
        this.moveCircle(circle, dt)
      })
    })
  },

  showCircle(circle) {
    gsap.to(circle, { duration: 0.35, opacity: 0.5 })
  },

  hideCircle(circle) {
    gsap.to(circle, { duration: 0.35, opacity: 0 })
  },

  moveCircle(circle, el) {
    const nav = document.querySelector('#navigation nav')
    const navTop = nav.getBoundingClientRect().top
    this.showCircle(circle)
    const top = el.getBoundingClientRect().top
    gsap.to(circle, { ease: 'expo.ease', duration: 0.35, top: top - navTop })
  },

  animateNav() {
    const targets = [
      Dom.find('#navigation-content header'),
      Dom.find('#navigation-content .current-user'),
      Dom.all('#navigation-content .navigation-section > *')
    ]
    gsap.to(targets, { duration: 0.35, x: 0, stagger: 0.02, ease: 'circ.out' })
    gsap.to(targets, { duration: 0.35, opacity: 1, stagger: 0.02, ease: 'none' })
  },

  destroyed() {
    console.log('(!) Brando.Navigation destroyed')
  }
})
