import { Dom } from '@brandocms/jupiter'
import { animate, animationTracker, ease, set, stagger } from '../../motion'

const OPEN_KEY = 'brando:nav:open'

export default app => ({
  mounted() {
    console.log('==> Navigation mounted.')
    this.animations = animationTracker()
    const $navigation = Dom.find('#navigation')
    if (!$navigation) {
      return
    }
    this.setupNavDropdowns()
    this.setupCurrentUserDropdown()

    // The sidebar stays mounted while pages change under it, so which item
    // is current is worked out here, on load and after every navigation.
    this.refreshActive = () => this.markActive()
    window.addEventListener('phx:page-loading-stop', this.refreshActive)
    this.markActive()
  },

  // The link for the page we are on: the one whose path is the longest
  // prefix of the current path ("/admin" alone would match everything). Its
  // section is opened if it sits in a closed one.
  markActive() {
    const path = window.location.pathname
    const links = Array.from(document.querySelectorAll('#nav a[href]'))
    let current = null
    let longest = -1

    links.forEach(a => {
      const href = new URL(a.href, window.location.origin).pathname
      const matches = path === href || path.startsWith(href.endsWith('/') ? href : href + '/')
      if (matches && href.length > longest) {
        current = a
        longest = href.length
      }
    })

    links.forEach(a => a.classList.toggle('active', a === current))

    const trigger = current?.closest('dl')?.querySelector('[data-nav-expand]')
    if (trigger && current.closest('dd') && !trigger.classList.contains('open')) this.openDropdown(trigger)
  },

  setupCurrentUserDropdown() {
    this.$currentUserDropdown = document.querySelector('#current-user')
    if (!this.$currentUserDropdown) {
      return
    }
    this.$currentUserDropdownContent = Dom.find(this.$currentUserDropdown, '.dropdown-content')
    this.currentUserDropdownOpen = false
    this.currentUserIconRotation = 0
    this.$currentUserDropdown.addEventListener('click', e => {
      this.toggleCurrentUserDropdown()
    })
  },

  toggleCurrentUserDropdown() {
    const lis = this.$currentUserDropdownContent.querySelectorAll('li')
    const { track } = this.animations

    // Quick: the row is one line of content, and a slow reveal made it feel
    // heavier than the menu groups around it. The icon keeps turning the same
    // way, half a turn per click.
    this.currentUserIconRotation += 180
    track(
      animate(
        this.$currentUserDropdown.querySelector('.dropdown-icon'),
        { rotate: this.currentUserIconRotation },
        { duration: 0.2 }
      )
    )
    this.$currentUserDropdown.classList.toggle('open', !this.currentUserDropdownOpen)
    if (this.currentUserDropdownOpen) {
      this.hideItems(lis, { duration: 0.12, delay: stagger(0.03) })
      track(
        animate(
          this.$currentUserDropdown,
          { height: `${this.height}px` },
          { duration: 0.18, delay: 0.05, ease: ease.power2InOut }
        )
      )
      this.currentUserDropdownOpen = false
    } else {
      // The closed height, measured once: a click during the closing animation
      // would otherwise record a half-open height to close to.
      this.height ??= this.$currentUserDropdown.offsetHeight

      track(animate(this.$currentUserDropdown, { height: 'auto' }, { duration: 0.18, ease: ease.power2Out }))
      this.showItems(lis, { duration: 0.15, delay: stagger(0.03, { startDelay: 0.06 }) })
      this.currentUserDropdownOpen = true
    }
  },

  // GSAP's autoAlpha: items are faded and then hidden, so a collapsed menu
  // cannot be tabbed into. A fade that is interrupted never finishes, and so
  // never hides items that are being shown again. `containers` (a grouped
  // section's role="group" wrappers) are hidden and shown with their items,
  // so a closed section leaves no empty named groups for screen readers.
  hideItems(items, options, containers = []) {
    const animation = animate(Array.from(items).reverse(), { opacity: 0, x: -6 }, options)
    this.animations
      .track(animation)
      .finished.then(() => set([...containers, ...items], { visibility: 'hidden' }))
  },

  showItems(items, options, containers = []) {
    set([...containers, ...items], { visibility: 'visible' })
    this.animations.track(animate(items, { opacity: [0, 1], x: [-6, 0] }, options))
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

  // What a section fades in and hides: its links, and the headings of a
  // grouped one (Configuration), in reading order. Hidden headings leave the
  // accessibility tree with the links under them.
  dropdownRows(dd) {
    return dd.querySelectorAll('li, .nav-group-label')
  },

  // The role="group" wrappers around a grouped section's headings and links.
  dropdownGroups(dd) {
    return Array.from(dd.querySelectorAll('.nav-group'))
  },

  // Opens a section at once, without the animation: on load, for sections
  // that were open, or that hold the current page. Instant animations rather
  // than plain styles, so Motion knows where a later toggle starts from.
  openDropdown(trigger) {
    const dl = trigger.parentNode.parentNode
    const dd = dl.querySelector('dd')
    const lis = this.dropdownRows(dd)
    // Measured once, while the section is closed: see toggleCurrentUserDropdown.
    trigger.dataset.height ||= dl.offsetHeight
    set(dd, { opacity: 1, display: 'block' })
    set([...this.dropdownGroups(dd), ...lis], { visibility: 'visible' })
    animate(lis, { opacity: 1, x: 0 }, { duration: 0 })
    animate(dl, { height: 'auto' }, { duration: 0 })
    trigger.classList.add('open')
  },

  toggleDropdown(trigger) {
    const dl = trigger.parentNode.parentNode
    const dd = dl.querySelector('dd')
    const lis = this.dropdownRows(dd)
    const { track } = this.animations

    if (trigger.classList.contains('open')) {
      this.hideItems(lis, { duration: 0.1, delay: stagger(0.015) }, this.dropdownGroups(dd))
      track(
        animate(
          dl,
          { height: `${trigger.dataset.height}px` },
          { duration: 0.18, delay: 0.04, ease: ease.power2InOut }
        )
      )
      trigger.classList.remove('open')
      this.saveOpen(trigger.dataset.navKey, false)
    } else {
      trigger.dataset.height ||= dl.offsetHeight
      set(dd, { opacity: 1, display: 'block' })
      track(animate(dl, { height: 'auto' }, { duration: 0.18, ease: ease.power2Out }))
      this.showItems(lis, { duration: 0.14, delay: stagger(0.02, { startDelay: 0.05 }) }, this.dropdownGroups(dd))
      trigger.classList.add('open')
      this.saveOpen(trigger.dataset.navKey, true)
    }
  },

  setupNavDropdowns() {
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

  destroyed() {
    window.removeEventListener('phx:page-loading-stop', this.refreshActive)
    this.animations.stopAll()
    console.log('(!) Brando.Navigation destroyed')
  }
})
