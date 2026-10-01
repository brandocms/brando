// Reports a preview <video>'s own size to the LiveView once its metadata
// loads, for videos whose record has no dimensions. The server only displays
// it (the video drawer's ratio); nothing is saved.
export default () => ({
  mounted() {
    this.report = () => {
      const { videoWidth: width, videoHeight: height } = this.el
      if (width && height) this.pushEventTo(this.el, 'video_preview_dimensions', { width, height })
    }

    this.el.addEventListener('loadedmetadata', this.report)
    if (this.el.readyState >= 1) this.report()
  },

  destroyed() {
    this.el.removeEventListener('loadedmetadata', this.report)
  }
})
