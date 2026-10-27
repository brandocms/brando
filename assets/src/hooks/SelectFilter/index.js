import { Dom } from '@brandocms/jupiter'

// Show/hide goes through LiveView's sticky JS commands (`this.js()` —
// addClass/removeClass funnel into DOM.putSticky), so the patcher re-applies
// the classes after every morphdom pass. Plain classList/inline-style
// mutations would be wiped when a selection patch re-renders the option
// list while the modal stays open. Styling lives in CSS (`.filter-hidden`,
// `.visible`) — inline styles are not sticky-covered.
export default (app) => ({
  mounted() {
    this.$input = Dom.find(this.el, 'input')
    this.$clearBtn = Dom.find(this.el, '.filter-clear')
    this._target = this.el.dataset.target || '.options-option'

    requestAnimationFrame(() => this.$input.focus())

    this.$input.addEventListener('input', () => {
      this.filter(this.$input.value.toLowerCase().trim())
    })

    this.$input.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && this.$input.value !== '') {
        e.stopPropagation()
        this.clear()
      } else if (e.key === 'Enter' && this.el.hasAttribute('data-enter-select')) {
        // the input sits inside the entry or block form: Enter must not submit it
        e.preventDefault()
        this.selectOnlyMatch()
      }
    })

    if (this.$clearBtn) {
      this.$clearBtn.addEventListener('click', () => {
        this.clear()
        this.$input.focus()
      })
    }
  },

  updated() {
    this.filter(this.$input.value.toLowerCase().trim())
  },

  getContainer() {
    // explicit target — falls back to legacy sibling coupling for
    // any external markup still relying on it
    if (this.el.dataset.filterTarget) {
      return document.querySelector(this.el.dataset.filterTarget)
    }
    return this.el.nextElementSibling
  },

  clear() {
    this.$input.value = ''
    this.filter('')
  },

  // `data-enter-select`: Enter on a filter that leaves one option picks it,
  // and closes the modal the filter sits in (its `data-modal-close`).
  selectOnlyMatch() {
    const $container = this.getContainer()
    if (!$container || this.$input.value.trim() === '') {
      return
    }

    const $visible = Dom.all($container, this._target).filter((option) => !option.classList.contains('filter-hidden'))
    if ($visible.length !== 1) {
      return
    }

    $visible[0].click()

    const $modal = this.el.closest('.modal[data-modal-close]')
    if ($modal) {
      app.liveSocket.execJS($modal, $modal.dataset.modalClose)
    }
  },

  // sticky class toggle: adds `klass` when `on`, removes it otherwise
  setClass(el, on, klass) {
    if (on) {
      this.js().addClass(el, [klass])
    } else {
      this.js().removeClass(el, [klass])
    }
  },

  filter(value) {
    const $container = this.getContainer()
    if (!$container) {
      return
    }

    const $options = Dom.all($container, this._target)
    let hiddenCount = 0

    $options.forEach((option) => {
      const matches = this.includes(option.dataset.label, value)
      if (!matches) hiddenCount += 1
      this.setClass(option, !matches, 'filter-hidden')
    })

    if (this.el.dataset.countTarget) {
      const count = document.querySelector(this.el.dataset.countTarget)
      if (count) count.textContent = $options.length - hiddenCount
    }

    if (this.$clearBtn) {
      this.setClass(this.$clearBtn, value !== '', 'visible')
    }

    const $noResults = Dom.find($container, '.no-results')
    if ($noResults) {
      const noneVisible = $options.length > 0 && hiddenCount === $options.length
      this.setClass($noResults, noneVisible, 'visible')
    }
  },

  includes(str, query) {
    if (str === undefined) str = 'undefined'
    if (str === null) str = 'null'
    if (str === false) str = 'false'
    const text = str.toString().toLowerCase()
    return text.indexOf(query.trim()) !== -1
  },
})
