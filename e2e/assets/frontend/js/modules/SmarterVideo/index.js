import { VidstackPlayer, PlyrLayout } from 'vidstack/global/player'
import RevealObserver from './RevealObserver'
import InViewObserver from './InViewObserver'

export default class SmartVideo {
  constructor(app, el, inVitro = false) {
    this.app = app
    this.el = el
    this.initialize()
  }

  initialize() {
    this.playing = false
    this.controls = this.el.hasAttribute('data-controls')
    this.progress = this.el.hasAttribute('data-progress')
    this.preload = this.el.hasAttribute('data-preload')
    this.title = this.el.getAttribute('data-title')
    this.video = this.el.querySelector('video')
    this.autoplay = this.video.hasAttribute('autoplay')
    this.playButton = this.el.querySelector('.video-play-button')
    this.revealObserver = new RevealObserver(this.el)
    this.video.setAttribute('data-view-type', 'video')
    this.video.setAttribute('data-media-time-slider', '')

    this.opts = {
      controls: this.controls,
      progress: this.progress,
      preload: this.preload,
      title: this.title,
      playButton: this.playButton,
      autoplay: this.autoplay,
    }

    return VidstackPlayer.create({
      target: this.video,
      title: this.title,
      load: this.preload ? 'visible' : 'eager',
      hideControlsOnMouseLeave: false,
      layout: this.progress
        ? new PlyrLayout({
            controls: this.buildControls(this.opts),
          })
        : null,
    }).then((player) => {
      this.player = player
      this.player.controls.hideOnMouseLeave = false
      this.player.controls.hideDelay = 350
      this.inViewObserver = new InViewObserver(this.el, this)

      this.video = this.el.querySelector('video')
      this.video.addEventListener('click', (event) => {
        if (this.player.state.paused) {
          const playingPlayers = this.app.smartVideos.filter((v) => {
            return v.playing && v.playButton
          })
          playingPlayers.forEach((player) => (player.player.paused = true))
          this.player.paused = false
        } else {
          this.player.paused = true
        }
      })

      this.player.addEventListener('can-play', (event) => {
        this.el.setAttribute('data-can-play', '')
      })

      this.player.addEventListener('play', (event) => {
        this.el.setAttribute('data-playing', '')
        this.playing = true
      })

      this.player.addEventListener('ended', (event) => {
        this.el.removeAttribute('data-playing', '')
        this.playing = false
      })

      this.player.addEventListener('pause', (event) => {
        this.el.removeAttribute('data-playing', '')
        this.playing = false
      })
    })
  }

  buildControls(opts) {
    let controls = []
    if (opts.playButton) {
      controls.push('play')
    }
    if (opts.progress) {
      controls.push('progress')
    }
    if (opts.time) {
      controls.push('current-time')
    }
    if (opts.volume) {
      controls.push('volume')
    }
    if (opts.captions) {
      controls.push('captions')
    }
    if (opts.speed) {
      controls.push('settings')
    }
    if (opts.fullscreen) {
      controls.push('fullscreen')
    }

    return controls
  }
}
