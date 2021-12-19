import { Dom, gsap } from '@brandocms/jupiter'
import Picker from 'vanilla-picker/csp'

export default (app) => ({
  mounted () {
    console.log('Mounted ???') 
    const initialColor = this.el.dataset.color
    const inputTarget = Dom.find(this.el.dataset.input)

    const circle = this.el.querySelector('.circle')
    const colorHex = this.el.querySelector('.color-hex')

    circle.style.background = initialColor
    colorHex.innerHTML = initialColor

    const parent = this.el.querySelector('.picker-target')
    const picker = new Picker({ parent: parent, popup: 'left', color: '#000000' })

    // You can do what you want with the chosen color using two callbacks: onChange and onDone.
    picker.onChange = function (color) {
      inputTarget.value = color.hex
      circle.style.background = color.hex
      colorHex.innerHTML = color.hex
      inputTarget.dispatchEvent(new Event('input', { bubbles: true }))
    };
  }
})