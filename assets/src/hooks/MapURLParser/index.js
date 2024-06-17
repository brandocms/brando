import { Dom } from '@brandocms/jupiter'
import { alertError } from '../../alerts'

const GMAPS_REGEX = /<iframe(?:.*)src="(.*?)"/

const PROVIDERS = {
  gmaps: {
    regex: GMAPS_REGEX
  }
}

export default app => ({
  mounted() {
    this.target = this.el.dataset.target
    this.bindInput()
    this.source = null
    this.embedUrl = null
  },

  bindInput() {
    this.$button = Dom.find(this.el, 'button')
    this.$input = Dom.find(this.el, 'textarea')
    this.$modalButton = this.el
      .closest('.modal-content')
      .querySelector('.modal-footer button.primary')
    this.$button.addEventListener('click', () => {
      this.handleInput(this.$input.value)
      if (this.source && this.embedUrl) {
        this.pushEventTo(this.target, 'url', { source: this.source, embedUrl: this.embedUrl })
        if (this.$modalButton) {
          this.$modalButton.click()
        }
      } else {
        alertError(
          'Parsing failed',
          'Could not parse map URL. Make sure you are pasting the embed code.'
        )
      }
    })
  },

  handleInput(url) {
    let match

    for (const key of Object.keys(PROVIDERS)) {
      const provider = PROVIDERS[key]
      match = provider.regex.exec(url)

      if (match !== null && match[1] !== undefined) {
        this.source = key
        this.embedUrl = match[1]
        break
      }
    }
    if (!{}.hasOwnProperty.call(PROVIDERS, this.source)) {
      return false
    }
  }
})
