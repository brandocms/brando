// No input for this long, or the tab hidden, and the editor shows as away
const IDLE_AFTER = 30000
const ACTIVITY_EVENTS = ['mousemove', 'keydown', 'mousedown', 'touchstart']

export default class Presence {
  constructor(app) {
    this.app = app
  }

  trackIdle() {
    // Called on every lobby join, rejoins included; one checker is enough
    if (this.trackingIdle) return
    this.trackingIdle = true

    let idle = false
    let timer = null

    const goIdle = () => {
      if (idle) return
      idle = true
      this.setActive(false)
    }

    const activity = () => {
      clearTimeout(timer)
      timer = setTimeout(goIdle, IDLE_AFTER)
      if (!idle) return
      idle = false
      this.setActive(true)
    }

    for (const event of ACTIVITY_EVENTS) window.addEventListener(event, activity, { passive: true })

    document.addEventListener('visibilitychange', () => {
      if (document.hidden) {
        clearTimeout(timer)
        goIdle()
      } else {
        activity()
      }
    })

    timer = setTimeout(goIdle, IDLE_AFTER)
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
