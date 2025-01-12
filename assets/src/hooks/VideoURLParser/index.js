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

// A helper function to load a video element and extract its dimensions
async function getVideoDimensions(url) {
  return new Promise((resolve, reject) => {
    const video = document.createElement('video')
    // In many browsers/headless setups, you need to mute + autoplay
    // to avoid any permission issues
    video.autoplay = true
    video.muted = true
    video.src = url

    const onLoadedMetadata = () => {
      // We have width/height once metadata is loaded
      const width = video.videoWidth
      const height = video.videoHeight
      cleanup()
      if (width && height) {
        resolve({ width, height })
      } else {
        reject(new Error('Could not read video width/height.'))
      }
    }

    const onError = () => {
      cleanup()
      // If we have a MediaError object, surface that info
      const mediaError = video.error
      if (mediaError) {
        // Some browsers do not populate mediaError.message, but .code is standard:
        // 1: MEDIA_ERR_ABORTED
        // 2: MEDIA_ERR_NETWORK
        // 3: MEDIA_ERR_DECODE
        // 4: MEDIA_ERR_SRC_NOT_SUPPORTED
        reject(
          new Error(
            `Video load error (code ${mediaError.code}): ${mediaError.message || 'No detailed message'}`
          )
        )
      } else {
        reject(new Error('Unknown video load error.'))
      }
    }

    function cleanup() {
      video.removeEventListener('loadedmetadata', onLoadedMetadata)
      video.removeEventListener('error', onError)
      video.remove()
    }

    video.addEventListener('loadedmetadata', onLoadedMetadata, { once: true })
    video.addEventListener('error', onError, { once: true })
  })
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
      try {
        await this.handleInput(this.$input.value)
        this.pushEventTo(this.target, 'url', {
          width: this.width || 0,
          height: this.height || 0,
          source: this.source,
          remoteId: this.remoteId,
          url: this.$input.value,
        })
      } catch (err) {
        console.error(err)
        // ship what we have
        this.pushEventTo(this.target, 'url', {
          width: this.width || 0,
          height: this.height || 0,
          source: this.source,
          remoteId: this.remoteId,
          url: this.$input.value,
        })
      }
    })
  },

  handleInput(url) {
    let match
    this.url = url

    return new Promise(async (resolve, reject) => {
      this.resolve = resolve

      // Some Vimeo “file”-style links have special handling
      if (
        url.startsWith('https://player.vimeo.com/external/') ||
        url.startsWith('https://player.vimeo.com/progressive_redirect/')
      ) {
        this.source = 'file'
        this.remoteId = url

        try {
          const { width, height } = await getVideoDimensions(url)
          this.width = width
          this.height = height
          resolve()
        } catch (e) {
          reject(e)
        }
      } else {
        // Otherwise, check standard provider patterns
        for (const key of Object.keys(PROVIDERS)) {
          const provider = PROVIDERS[key]
          match = provider.regex.exec(url)

          if (match !== null && match[1] !== undefined) {
            this.source = key
            this.remoteId = match[1]
            resolve()
            break
          }
        }

        if (!{}.hasOwnProperty.call(PROVIDERS, this.source)) {
          reject(new Error('VideoURLParser: Unknown video source'))
          return false
        }
      }
    })
  },
})
