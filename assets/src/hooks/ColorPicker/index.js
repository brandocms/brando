import { Dom } from '@brandocms/jupiter'
import Picker from 'vanilla-picker/csp'

export default (app) => ({
  mounted () {
    const initialColor = this.el.dataset.color
    const inputTarget = Dom.find(this.el.dataset.input)

    this.circle = this.el.querySelector('.circle')
    this.colorHex = this.el.querySelector('.color-hex')

    this.setColor(initialColor)

    const parent = this.el.querySelector('.picker-target')
    this.picker = new Picker({ parent: parent, popup: 'top', color: initialColor || '#000000', alpha: false })

    // You can do what you want with the chosen color using two callbacks: onChange and onDone.
    this.picker.onChange = function (color) {
      let processedColor = color.printHex(false)
      if (processedColor === 9 && processedColor.slice(-2) === 'ff') {
        processedColor = processedColor.slice(0, -2)
      }
      inputTarget.value = processedColor
      this.circle.style.background = processedColor
      this.colorHex.innerHTML = processedColor
      inputTarget.dispatchEvent(new Event('input', { bubbles: true }))
    }

    const observer = new MutationObserver(mutations => {
      mutations.forEach(mutation => {
        if (mutation.type === 'attributes' && mutation.attributeName === 'data-color') {
          const currentColor = this.el.dataset.color
          this.setColor(currentColor)
        }
      })
    })

    observer.observe(this.el, {
      attributes: true //configure it to listen to attribute changes
    })
  },

  setColor (color) {
    this.circle.style.background = color
    this.colorHex.innerHTML = color
  }
})
