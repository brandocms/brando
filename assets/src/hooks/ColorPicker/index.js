import { Dom } from '@brandocms/jupiter'
import Picker from 'vanilla-picker/csp'

export default (app) => ({
  mounted () {
    const initialColor = this.el.dataset.color
    const inputTarget = Dom.find(this.el.dataset.input)

    const circle = this.el.querySelector('.circle')
    const colorHex = this.el.querySelector('.color-hex')

    circle.style.background = initialColor
    colorHex.innerHTML = initialColor

    const parent = this.el.querySelector('.picker-target')
    const picker = new Picker({ parent: parent, popup: 'left', color: initialColor || '#000000', alpha: false })

    // You can do what you want with the chosen color using two callbacks: onChange and onDone.
    picker.onChange = function (color) {
      let processedColor = color.printHex(false)
      if (processedColor === 9 && processedColor.slice(-2) === 'ff') {
        processedColor = processedColor.slice(0, -2)
      }
      inputTarget.value = processedColor
      circle.style.background = processedColor
      colorHex.innerHTML = processedColor
      inputTarget.dispatchEvent(new Event('input', { bubbles: true }))
    }
  }
})