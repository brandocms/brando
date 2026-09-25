// Plays a video file or stream in a <video> element. HLS streams (.m3u8) play
// natively only in Safari, so elsewhere hls.js is loaded, on first use.
export default () => ({
  mounted() {
    this.load(this.el.dataset.src)
  },

  updated() {
    if (this.el.dataset.src !== this.src) this.load(this.el.dataset.src)
  },

  destroyed() {
    this.teardown()
  },

  async load(src) {
    this.teardown()
    this.src = src
    if (!src) return

    const hls = /\.m3u8(\?|$)/.test(src)

    if (!hls || this.el.canPlayType('application/vnd.apple.mpegurl')) {
      this.el.src = src
      return
    }

    const { default: Hls } = await import('hls.js')
    // The element may have moved on while hls.js loaded.
    if (this.src !== src) return

    if (Hls.isSupported()) {
      this.hls = new Hls()
      this.hls.loadSource(src)
      this.hls.attachMedia(this.el)
    } else {
      this.el.src = src
    }
  },

  teardown() {
    if (this.hls) {
      this.hls.destroy()
      this.hls = null
    }
  },
})
