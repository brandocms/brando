import IdleJs from 'idle-js'

export default class Presence {
  constructor(app) {
    this.app = app
  }

  trackIdle() {
    // Called on every lobby join, rejoins included; one checker is enough
    if (this.idle) return

    this.idle = new IdleJs({
      idle: 30000, // idle time in ms
      events: ['mousemove', 'keydown', 'mousedown', 'touchstart'], // events that will trigger the idle resetter
      onIdle: () => {
        this.setActive(false)
      },
      onActive: () => {
        this.setActive(true)
      },
      onHide: () => {
        this.setActive(false)
      },
      onShow: () => {
        this.setActive(true)
      },
      keepTracking: true,
      startAtIdle: false
    })

    this.idle.start()
  }

  setActive(status) {
    if (this.app.lobbyChannel) {
      this.app.lobbyChannel.push('user:state', { active: status })
    }
  }

  setUrl(url) {
    if (this.app.lobbyChannel) {
      this.app.lobbyChannel.push('user:state', { url })
    }
  }
}
