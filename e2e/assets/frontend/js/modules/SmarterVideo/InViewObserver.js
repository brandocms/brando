export default class InViewObserver {
  constructor(el, smartVideo) {
    this.el = el
    this.smartVideo = smartVideo
    if (!this.smartVideo.opts.autoplay) {
      return
    }
    this.observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            if (this.smartVideo.player.state.paused) {
              this.smartVideo.player.paused = false
            }
          } else {
            if (this.smartVideo.player.state.playing) {
              this.smartVideo.player.paused = true
            }
          }
        })
      },
      {
        rootMargin: '10%',
        threshold: 0.0,
      }
    )

    this.observer.observe(this.el)
  }
}
