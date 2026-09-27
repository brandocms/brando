import { Dom, gsap } from '@brandocms/jupiter'

const OPEN_KEY = 'brando:nav:open'

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
    if (!this.$currentUserDropdown) {
      return
    }
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

  // Which sidebar sections are open survives page loads: the keys (item
  // names) of the open ones are kept in localStorage.
  savedOpen() {
    try {
      return JSON.parse(localStorage.getItem(OPEN_KEY) || '[]')
    } catch (_e) {
      return []
    }
  },

  saveOpen(key, open) {
    const keys = this.savedOpen().filter(k => k !== key)
    if (open) keys.push(key)
    try {
      localStorage.setItem(OPEN_KEY, JSON.stringify(keys))
    } catch (_e) {
      // storage full or disabled: the sidebar just doesn't remember
    }
  },

  // Opens a section at once, without the animation: on load, for sections
  // that were open, or that hold the current page.
  openDropdown(trigger) {
    const dl = trigger.parentNode.parentNode
    const dd = dl.querySelector('dd')
    trigger.dataset.height = dl.offsetHeight
    gsap.set(dd, { opacity: 1, display: 'block' })
    gsap.set(dd.querySelectorAll('li'), { autoAlpha: 1, x: 0 })
    gsap.set(dl, { height: 'auto' })
    trigger.classList.add('open')
  },

  toggleDropdown(trigger) {
    const dl = trigger.parentNode.parentNode
    const dd = dl.querySelector('dd')
    const lis = dd.querySelectorAll('li')

    if (trigger.classList.contains('open')) {
      gsap.to(Array.from(lis).reverse(), { duration: 0.35, autoAlpha: 0, x: -15, stagger: 0.03 })
      gsap.to(dl, { duration: 0.35, delay: 0.2, height: trigger.dataset.height })
      trigger.classList.remove('open')
      this.saveOpen(trigger.dataset.navKey, false)
    } else {
      trigger.dataset.height = dl.offsetHeight
      gsap.set(dl, { height: trigger.dataset.height })
      gsap.set(lis, { autoAlpha: 0, x: -15 })
      gsap.set(dd, { opacity: 1, display: 'block' })
      gsap.to(dl, { duration: 0.35, height: 'auto' })
      gsap.to(lis, { duration: 0.2, delay: 0.2, autoAlpha: 1, x: 0, stagger: 0.02 })
      trigger.classList.add('open')
      this.saveOpen(trigger.dataset.navKey, true)
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
    const saved = this.savedOpen()
    const path = window.location.pathname

    dropdowns.forEach(dd => {
      const links = dd.parentNode.parentNode.querySelectorAll('dd a[href]')
      const holdsCurrent = Array.from(links).some(a => {
        const href = new URL(a.href, window.location.origin).pathname
        return path === href || path.startsWith(href + '/')
      })

      if (saved.includes(dd.dataset.navKey) || holdsCurrent) this.openDropdown(dd)
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
    gsap.to(circle, { ease: 'power2.inOut', duration: 0.5, top: top - navTop })
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
