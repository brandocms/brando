import { Dom, gsap } from '@brandocms/jupiter'
import autosize from 'autosize'
import Sortable from 'sortablejs'

export default (app) => ({
  mounted() {
    this.$wrapper = this.el.closest('[data-block-index]')
    this.$baseBlock = this.el.closest('.base-block')
    this.index = parseInt(this.$wrapper.dataset.blockIndex)

    this.el.addEventListener('mouseover', e => {
      this.el.setAttribute('data-b-hover', '')
    })
    this.el.addEventListener('mouseleave', e => {
      this.el.removeAttribute('data-b-hover')
    })

    this.autosized = this.el.querySelectorAll('[data-autosize]')
    this.bindSortable()
    this.autosizeElements()
    this.reveal()
  },

  reveal() {
    const description = this.el.querySelectorAll('.block-description')
    const content = this.el.querySelectorAll('.block-content')
    const actions = this.el.querySelectorAll('.block-actions')

    // this.timeline = gsap.timeline()

    // this.timeline
    //   .to(this.$baseBlock, { duration: 0.2, opacity: 1, ease: 'none' }, '<')
    //   .to([description, content, actions], { duration: 0.2, opacity: 1, stagger: 0.08, ease: 'none' }, '<0.08')
    //   .call(() => {
    //     this.$baseBlock.dataset.bInitialized = ''
    //   })
  },

  autosizeElements() {
    Array.from(this.autosized).forEach(el => autosize(el))
  },

  updated() {
    this.autosizeElements()
  },

  bindSortable() {
    this.$blocksWrapper = this.el.closest('.blocks-wrapper')

    this.sortable = new Sortable(this.$blocksWrapper, {
      animation: 150,
      ghostClass: 'is-sorting',
      // swapThreshold: 0.50,
      sort: true,
      handle: '.block-action.move',
      dataIdAttr: 'data-block-index',
      draggable: '> [data-phx-component][data-block-uid]',
      store: {
        get: this.getOrder.bind(this),
        set: this.setOrder.bind(this)
      }
    })
  },

  getOrder() {

  },

  setOrder() {
    let order = this.sortable.toArray().map(Number)
    this.pushEventTo(this.el, 'blocks:reorder', { order })
  }
})