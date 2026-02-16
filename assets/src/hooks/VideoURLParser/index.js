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
    video.preload = 'metadata'
    video.crossOrigin = 'anonymous' // Handle CORS for video files
    video.src = url

    // Add timeout to prevent hanging
    const timeout = setTimeout(() => {
      cleanup()
      reject(new Error('Video dimension detection timed out after 10 seconds'))
    }, 10000)

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
        const errorMessages = {
          1: 'MEDIA_ERR_ABORTED',
          2: 'MEDIA_ERR_NETWORK',
          3: 'MEDIA_ERR_DECODE',
          4: 'MEDIA_ERR_SRC_NOT_SUPPORTED'
        }
        reject(
          new Error(
            `Video load error (${errorMessages[mediaError.code] || mediaError.code}): ${mediaError.message || 'No detailed message'}`
          )
        )
      } else {
        reject(new Error('Unknown video load error.'))
      }
    }

    function cleanup() {
      clearTimeout(timeout)
      video.removeEventListener('loadedmetadata', onLoadedMetadata)
      video.removeEventListener('error', onError)
      video.src = '' // Clear src to stop any loading
      video.remove()
    }

    video.addEventListener('loadedmetadata', onLoadedMetadata, { once: true })
    video.addEventListener('error', onError, { once: true })
  })
}

// Parse an HLS manifest to extract the highest resolution
async function getHLSDimensions(url) {
  const response = await fetch(url)
  const text = await response.text()

  let maxWidth = 0
  let maxHeight = 0

  const lines = text.split('\n')
  for (const line of lines) {
    const match = line.match(/RESOLUTION=(\d+)x(\d+)/)
    if (match) {
      const w = parseInt(match[1], 10)
      const h = parseInt(match[2], 10)
      if (w * h > maxWidth * maxHeight) {
        maxWidth = w
        maxHeight = h
      }
    }
  }

  if (maxWidth && maxHeight) {
    return { width: maxWidth, height: maxHeight }
  }

  throw new Error('No RESOLUTION found in HLS manifest')
}

function isHLSUrl(url) {
  return /\.m3u8($|\?)/i.test(url)
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
    this.url = url.trim()

    // Basic URL validation
    if (!this.url) {
      return Promise.reject(new Error('VideoURLParser: Empty URL provided'))
    }

    try {
      new URL(this.url)
    } catch {
      return Promise.reject(new Error('VideoURLParser: Invalid URL format'))
    }

    return new Promise(async (resolve, reject) => {
      this.resolve = resolve

      // Some Vimeo "file"-style links have special handling
      if (
        this.url.startsWith('https://player.vimeo.com/external/') ||
        this.url.startsWith('https://player.vimeo.com/progressive_redirect/')
      ) {
        this.source = 'file'
        this.remoteId = this.url

        try {
          const { width, height } = isHLSUrl(this.url)
            ? await getHLSDimensions(this.url)
            : await getVideoDimensions(this.url)
          this.width = width
          this.height = height
          resolve()
        } catch (e) {
          // For direct video files, still resolve but without dimensions
          console.warn('Could not get video dimensions:', e.message)
          this.width = 0
          this.height = 0
          resolve()
        }
      } else {
        // Otherwise, check standard provider patterns
        let sourceFound = false

        for (const key of Object.keys(PROVIDERS)) {
          const provider = PROVIDERS[key]
          match = provider.regex.exec(this.url)

          if (match !== null && match[1] !== undefined) {
            this.source = key
            this.remoteId = match[1]
            sourceFound = true

            // For direct video files, try to get dimensions
            if (key === 'file') {
              try {
                const { width, height } = isHLSUrl(this.url)
                  ? await getHLSDimensions(this.url)
                  : await getVideoDimensions(this.url)
                this.width = width
                this.height = height
              } catch (e) {
                console.warn('Could not get video dimensions for file:', e.message)
                this.width = 0
                this.height = 0
              }
            }

            resolve()
            break
          }
        }

        if (!sourceFound) {
          reject(new Error('VideoURLParser: URL does not match any supported video provider (YouTube, Vimeo, or direct video file)'))
        }
      }
    })
  },
})
