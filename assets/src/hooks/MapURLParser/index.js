import { Dom } from '@brandocms/jupiter'

const GMAPS_REGEX = /<iframe(?:.*)src="(.*?)"/

const PROVIDERS = {
  gmaps: {
    regex: GMAPS_REGEX,
  }
}

export default (app) => ({
  mounted() {
    this.target = this.el.dataset.target
    this.bindInput()
  },

  bindInput() {
    this.$button = Dom.find(this.el, 'button')
    this.$input = Dom.find(this.el, 'input')
    this.$button.addEventListener('click', () => {
      this.handleInput(this.$input.value)
      this.pushEventTo(this.target, 'url', { source: this.source, embedUrl: this.embedUrl })
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