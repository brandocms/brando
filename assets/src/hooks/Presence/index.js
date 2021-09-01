import { Dom, gsap } from '@brandocms/jupiter'

export default (app) => ({
  mounted() {
    console.log('==> Brando.Presence mounted')
    // update users
    this.setupListener()

    setTimeout(() => {
      this.updateUsers()
      this.getState()
      this.track()
    }, 1000)
  },

  setupListener() {
    this.handleEvent('b:presence:diff', ({ joins, leaves }) => {
      this.handleJoins(joins)
      this.handleLeaves(leaves)
    })
  },

  handleJoins(joins) {
    for (let i in joins) {
      const user = Dom.find(`.user-presence[data-idx="${i}"]`)
      if (user) {
        user.dataset.userStatus = 'online'
      }
    }
  },

  handleLeaves(leaves) {
    for (let i in leaves) {
      const user = Dom.find(`.user-presence[data-idx="${i}"]`)
      if (user) {
        user.dataset.userStatus = 'offline'
      }
    }
  },

  getState() {
    this.pushEventTo(this.el, 'get_state', {}, payload => {
      for (let i in payload.state) {
        const user = Dom.find(`.user-presence[data-idx="${i}"]`)
        if (user) {
          user.dataset.userStatus = 'online'
        }
      }
    })
  },

  updateUsers() {
    this.pushEventTo(this.el, 'get_users', {}, payload => {
      this.$presences = Dom.find('.presences')
      if (this.$presences) {

      } else {
        const presencesEl = document.createElement('div')
        presencesEl.className = 'presences'

        payload.users.forEach(u => {
          let userEl = document.createRange().createContextualFragment(`
              <a
                data-idx="${u.id}"
                data-user-status="offline"
                class="user-presence hidden">
                <div class="avatar">
                  <img src="${u.avatar}" />
                </div>
              </a>
            `)
          presencesEl.append(userEl)
        })
        document.body.append(presencesEl)
      }
    })
  },

  track() {
    this.pushEventTo(this.el, 'track', { userId: app.userId })
  }
})