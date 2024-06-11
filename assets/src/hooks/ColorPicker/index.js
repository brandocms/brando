import { Dom } from '@brandocms/jupiter'
import Picker from 'vanilla-picker/csp'
import debounce from 'lodash.debounce'

export default app => ({
  mounted() {
    this.picker = null
    const observer = new MutationObserver(mutations => {
      mutations.forEach(mutation => {
        if (mutation.type === 'attributes' && mutation.attributeName === 'data-color') {
          const currentColor = this.el.dataset.color
          this.setColor(currentColor)
        }

        if (mutation.type === 'attributes' && mutation.attributeName === 'data-opacity') {
          this.initialize()
          return
        }

        if (mutation.type === 'attributes' && mutation.attributeName === 'data-palette') {
          this.initialize()
          return
        }
      })
    })

    observer.observe(this.el, { attributes: true })
    this.initialize()
  },

  initialize() {
    if (this.picker) {
      this.picker.destroy()
    }

    const initialColor = this.el.dataset.color
    const opacity = this.el.hasAttribute('data-opacity')
    const inputTarget = Dom.find(this.el.dataset.input)
    const paletteColors = this.el.hasAttribute('data-palette')
      ? this.el.dataset.palette.split(',')
      : []

    this.lastColor = initialColor

    this.circle = this.el.querySelector('.circle')
    this.colorHex = this.el.querySelector('.color-hex')

    this.setColor(initialColor)

    const parent = this.el.querySelector('.picker-target')
    const that = this

    this.picker = new Picker({
      parent: parent,
      popup: 'bottom',
      color: initialColor || '#000000',
      alpha: opacity,

      onChange: debounce(color => {
        let processedColor = color.printHex(opacity)
        if (processedColor.length === 9 && processedColor.slice(-2) === 'ff') {
          processedColor = processedColor.slice(0, -2)
        }

        this.circle.style.background = processedColor
        this.colorHex.innerHTML = processedColor
        inputTarget.value = processedColor

        // has the color actually changed?
        if (this.lastColor.toLowerCase() !== processedColor) {
          inputTarget.dispatchEvent(new Event('input', { bubbles: true }))
        }

        this.lastColor = processedColor
      }, 100),

      onOpen: function () {
        this._colorToSplotch = {}
        this._domPalette = this.domElement.querySelectorAll('.picker_palette')[0]
        this._domPalette.innerHTML = ''
        this._colorToSplotch = {}
        for (let i = 0; i < paletteColors.length; i += 1) {
          const splotch = document.createElement('div')
          splotch.classList.add('picker_splotch')
          const c = new this.color.constructor(paletteColors[i])
          this._colorToSplotch[c.hslaString] = splotch
          splotch.addEventListener(
            'click',
            function (c, e) {
              this._setColor(c.hslaString)
            }.bind(this, c)
          )
          splotch.style.backgroundColor = c.hslaString
          this._domPalette.appendChild(splotch)
        }
      },

      template: `
      <div class="picker_wrapper" tabindex="-1">
        <div class="picker_arrow"></div>
        <div class="picker_hue picker_slider">
          <div class="picker_selector"></div>
        </div>
        <div class="picker_sl">
          <div class="picker_selector"></div>
        </div>
        <div class="picker_alpha picker_slider">
          <div class="picker_selector"></div>
        </div>
        <div class="picker_palette"></div>
        <div class="picker_editor">
          <input aria-label="Type a color name or hex value"/>
        </div>
        <div class="picker_sample"></div>
        <div class="picker_done">
          <button>Ok</button>
        </div>
        <div class="picker_cancel">
          <button>Cancel</button>
        </div>
      </div>
      `
    })
  },

  setColor(color) {
    this.circle.style.background = color
    this.colorHex.innerHTML = color
  }
})
