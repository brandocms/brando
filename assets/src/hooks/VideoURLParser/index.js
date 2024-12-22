import { Dom } from '@brandocms/jupiter'

const VIMEO_REGEX = /(?:http[s]?:\/\/)?(?:www.)?vimeo.com\/(.+)/
const YOUTUBE_REGEX =
  /(?:youtube\.com\/\S*(?:(?:\/e(?:mbed))?\/|watch\?(?:\S*?&?v=))|youtu\.be\/)([a-zA-Z0-9_-]{6,11})/
const FILE_REGEX = /(.*)/

const PROVIDERS = {
  vimeo: {
    regex: VIMEO_REGEX,
    html: [
      '<iframe src="{{protocol}}//player.vimeo.com/video/{{remote_id}}?title=0&byline=0" ',
      'frameborder="0"></iframe>',
    ].join('\n'),
  },
  youtube: {
    regex: YOUTUBE_REGEX,
    html: [
      '<iframe src="{{protocol}}//www.youtube.com/embed/{{remote_id}}" ',
      'width="580" height="320" frameborder="0" allowfullscreen></iframe>',
    ].join('\n'),
  },
  file: {
    regex: FILE_REGEX,
    html: [
      '<video class="villain-video-file" muted="muted" tabindex="-1" loop autoplay src="{{remote_id}}">',
      '<source src="{{remote_id}}" type="video/mp4">',
      '</video>',
    ].join('\n'),
  },
}

export default (app) => ({
  mounted() {
    this.target = this.el.dataset.target
    this.$loader = Dom.find(this.el, '.video-loading')
    this.bindInput()
  },

  loading() {
    Dom.removeClass(this.$loader, 'hidden')
  },

  bindInput() {
    this.$button = Dom.find(this.el, 'button')
    this.$input = Dom.find(this.el, 'input')
    this.$button.addEventListener('click', async () => {
      if (!this.$input.value) {
        return
      }
      this.loading()
      await this.handleInput(this.$input.value)
      this.pushEventTo(this.target, 'url', {
        width: this.width || 0,
        height: this.height || 0,
        source: this.source,
        remoteId: this.remoteId,
        url: this.$input.value,
      })
    })
  },

  handleInput(url) {
    let match
    this.url = url

    return new Promise((resolve) => {
      this.resolve = resolve
      if (
        url.startsWith('https://player.vimeo.com/external/') ||
        url.startsWith('https://player.vimeo.com/progressive_redirect/')
      ) {
        this.source = 'file'
        this.remoteId = url
        this.createVideoProxy()
      } else {
        for (const key of Object.keys(PROVIDERS)) {
          const provider = PROVIDERS[key]
          match = provider.regex.exec(url)

          if (match !== null && match[1] !== undefined) {
            this.source = key
            this.remoteId = match[1]
            this.resolve()
            break
          }
        }
        if (!{}.hasOwnProperty.call(PROVIDERS, this.source)) {
          return false
        }
      }
    })
  },

  createVideoProxy() {
    this.attempts = 0
    this.videoElement = document.createElement('video')
    this.videoElement.autoplay = true
    this._boundReadyListener = this.readyListener.bind(this)
    this.videoElement.addEventListener('loadeddata', this._boundReadyListener)
    this.videoElement.muted = true
    this.videoElement.src = this.url
  },

  readyListener() {
    this.findVideoSize()
  },

  findVideoSize() {
    if (this.videoElement.videoWidth > 0 && this.videoElement.videoHeight > 0) {
      this.videoElement.removeEventListener(
        'loadeddata',
        this._boundReadyListener
      )
      this.width = this.videoElement.videoWidth
      this.height = this.videoElement.videoHeight

      this.videoElement.remove()

      this.resolve()
    } else {
      if (this.attempts < 10) {
        this.attempts++
        setTimeout(this.findVideoSize, 400)
      } else {
        console.error('VideoURLParser: Could not find video dimensions')
      }
    }
  },
})
