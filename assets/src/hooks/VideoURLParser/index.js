import { Dom } from '@brandocms/jupiter'

const VIMEO_REGEX = /(?:http[s]?:\/\/)?(?:www.)?vimeo.com\/(.+)/
const YOUTUBE_REGEX = /(?:youtube\.com\/\S*(?:(?:\/e(?:mbed))?\/|watch\?(?:\S*?&?v=))|youtu\.be\/)([a-zA-Z0-9_-]{6,11})/
const FILE_REGEX = /(.*)/

const PROVIDERS = {
  vimeo: {
    regex: VIMEO_REGEX,
    html: [
      '<iframe src="{{protocol}}//player.vimeo.com/video/{{remote_id}}?title=0&byline=0" ',
      'frameborder="0"></iframe>'
    ].join('\n')
  },
  youtube: {
    regex: YOUTUBE_REGEX,
    html: ['<iframe src="{{protocol}}//www.youtube.com/embed/{{remote_id}}" ',
      'width="580" height="320" frameborder="0" allowfullscreen></iframe>'
    ].join('\n')
  },
  file: {
    regex: FILE_REGEX,
    html: ['<video class="villain-video-file" muted="muted" tabindex="-1" loop autoplay src="{{remote_id}}">',
      '<source src="{{remote_id}}" type="video/mp4">',
      '</video>'
    ].join('\n')
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
      this.pushEventTo(this.target, 'url', { source: this.source, remoteId: this.remoteId, url: this.$input.value })
    })
  },

  handleInput(url) {
    let match
    
    if (url.startsWith('https://player.vimeo.com/external/')) {
      this.source = 'file'
      this.remoteId = url
    } else {
      for (const key of Object.keys(PROVIDERS)) {
        const provider = PROVIDERS[key]
        match = provider.regex.exec(url)

        if (match !== null && match[1] !== undefined) {
          this.source = key
          this.remoteId = match[1]
          break
        }
      }
      if (!{}.hasOwnProperty.call(PROVIDERS, this.source)) {
        return false
      }
    }
  }
})