import { prefersReducedMotion } from '../../motion'

const incoming = '[data-assistant-step], .assistant-message.is-assistant, .assistant-progress'

// The server owns the text. Reveal new steps once, without retyping history on
// a patch, a conversation switch or a reconnect. WAAPI leaves no inline styles
// for LiveView to overwrite, and reserves the finished text's space from frame 1.
export default () => ({
  mounted() {
    this.running = new Set()
    this.remember()
  },

  remember() {
    this.conversation = this.el.dataset.conversation
    this.seen = new Set(Array.from(this.el.querySelectorAll(incoming), el => el.id))
  },

  updated() {
    const conversation = this.el.dataset.conversation
    if (this.suspended || conversation !== this.conversation) {
      this.stopAnimations()
      this.remember()
      return
    }
    this.conversation = conversation

    const nodes = Array.from(this.el.querySelectorAll(incoming))
    for (const el of nodes) {
      if (this.seen.has(el.id) || prefersReducedMotion()) continue
      if (el.hasAttribute('data-assistant-step')) {
        const words = Array.from(el.querySelectorAll('.assistant-step-word'))
        // A short typed cadence, capped so even a long label is readable quickly.
        const stagger = Math.min(32, 260 / Math.max(words.length - 1, 1))
        words.forEach((word, index) => this.animate(word, { opacity: [0, 1] }, {
          duration: 180, delay: index * stagger, easing: 'ease-out', fill: 'backwards',
        }))
        this.animate(el.querySelector('[data-icon]'), {
          opacity: [0, 1], transform: ['scale(.8)', 'scale(1)'],
        }, { duration: 300, easing: 'cubic-bezier(.22, 1, .36, 1)' })
      } else {
        this.animate(el, { opacity: [0, 1], transform: ['translateY(4px)', 'translateY(0)'] }, {
          duration: 350, easing: 'cubic-bezier(.22, 1, .36, 1)',
        })
      }
    }
    this.seen = new Set(nodes.map(el => el.id))
  },

  animate(el, frames, options) {
    if (!el) return
    const animation = el.animate(frames, options)
    this.running.add(animation)
    animation.finished.then(
      () => this.running.delete(animation),
      () => this.running.delete(animation),
    )
  },

  stopAnimations() {
    this.running.forEach(animation => animation.cancel())
    this.running.clear()
  },

  disconnected() {
    this.suspended = true
    this.stopAnimations()
  },

  reconnected() {
    this.remember()
    this.suspended = false
  },

  destroyed() {
    this.stopAnimations()
  },
})
