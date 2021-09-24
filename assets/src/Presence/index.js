import { gsap, Dom } from '@brandocms/jupiter'
import { Presence as PhoenixPresence } from 'phoenix'

export default class Presence {
  constructor (app) {
    this.app = app
    this.lobbyPresences = {}    
  }

  setUsers (users) {
    this.users = users
    this.createPresence()
  }

  storeLobbyPresences (state) {
    const lobbyPresences = PhoenixPresence.syncState(this.lobbyPresences, state)
    this.lobbyPresences = lobbyPresences
    this.checkUsers()
  }

  storeLobbyPresencesDiff (diff) {
    const lobbyPresences = PhoenixPresence.syncDiff(this.lobbyPresences, diff)
    this.lobbyPresences = lobbyPresences
    this.checkUsers()
  }

  checkUsers () {
    this.users.forEach(user => {
      const $user = Dom.find(`.user-presence[data-idx="${user.id}"]`)
      if (!$user) {
        return
      }

      if (this.lobbyPresences[user.id]) {
        $user.dataset.userStatus = 'online'
      } else {
        $user.dataset.userStatus = 'offline'
      }
    })
  }

  createPresence() {
    this.$presences = Dom.find('.presences')
    if (!this.$presences) {
      const presencesEl = document.createElement('div')
      presencesEl.className = 'presences'
      document.body.append(presencesEl)
      gsap.set(presencesEl, { display: 'none' })

      this.users.forEach(u => {
        let userEl = document.createRange().createContextualFragment(`
            <a
              data-idx="${u.id}"
              data-user-status="offline"
              class="user-presence">
              <div class="avatar">
                <img src="${u.avatar}" />
              </div>
            </a>
          `)
        presencesEl.append(userEl)
      })      

      const $users = Dom.all(presencesEl, 'a')
      console.log($users)
      gsap.set($users, { yPercent: 150 })
      gsap.set(presencesEl, { display: 'flex' })
      setTimeout(() => {
        gsap.to($users, { yPercent: 0, ease: 'circ.out', stagger: 0.3 })
      }, 3000)
    }
  }
}