<template>
  <div
    v-if="token && !loading"
    id="app"
    :class="{'loaded': !loading, 'menu-open': status, 'fullscreen': fullScreen}">
    <NProgress />
    <NavMenu />
    <NavBar />
    <transition
      name="fade"
      appear>
      <KProgress
        v-show="showProgress"
        :status="progressStatus" />
    </transition>
    <div id="content">
      <transition
        name="fade"
        mode="out-in"
        appear
        @after-leave="afterLeave">
        <router-view class="view" />
      </transition>
    </div>
  </div>
  <div v-else-if="!token">
    <div id="content">
      <transition
        name="fade"
        mode="out-in"
        appear
        @after-leave="afterLeave">
        <router-view class="view" />
      </transition>
    </div>
  </div>
</template>

<script>

import { mapActions, mapGetters } from 'vuex'
import apollo from 'brandojs/lib/api/apolloClient'
import NavBar from 'brandojs/lib/components/navigation/NavBar.vue'
import NavMenu from 'brandojs/lib/components/navigation/NavMenu.vue'
import NProgress from 'brandojs/lib/components/navigation/NProgress.vue'
import KProgress from 'brandojs/lib/components/navigation/KProgress.vue'

export default {
  components: {
    NavMenu,
    NavBar,
    NProgress,
    KProgress
  },

  data () {
    return {
      loading: 1,
      fullScreen: false,
      showProgress: false,
      progressStatus: {},
      progressPercent: null
    }
  },

  computed: {
    ...mapGetters('users', [
      'me',
      'token'
    ]),
    ...mapGetters('menu', [
      'status'
    ])
  },

  provide () {
    const userChannel = {}
    const adminChannel = {}

    Object.defineProperty(userChannel, 'channel', {
      enumerable: true,
      get: () => this.userChannel
    })

    Object.defineProperty(adminChannel, 'channel', {
      enumerable: true,
      get: () => this.adminChannel
    })

    return { userChannel, adminChannel }
  },

  watch: {
    token (value) {
      if (value) {
        this.initializeApp()
      }
    },

    '$route' () {
      if (this.$route.meta.fullScreen) {
        this.fullScreen = true
      } else {
        this.fullScreen = false
      }
    }
  },

  async created () {
    console.debug('created <App />')

    if (this.$route.meta.fullScreen) {
      this.fullScreen = true
    }

    if (this.token) {
      // check if the token is valid — might be old
      let fmData = new FormData()
      fmData.append('jwt', this.token)

      const response = await fetch('/admin/auth/verify', {
        method: 'post',
        body: fmData
      })

      switch (response.status) {
        case 200:
          await this.initializeApp()
          break
        case 406:
          this.$store.commit('users/REMOVE_TOKEN')
          window.location = '/admin/login?expired=true'
          break
        case 401:
          this.$store.commit('users/REMOVE_TOKEN')
          window.location = '/admin/login?expired=true'
      }
    } else {
      this.loading = false
      this.loaded = true
    }
  },

  methods: {
    async initializeApp () {
      this.initializeApolloClient()
      this.connectSocket()
      try {
        await this.storeMe()
        await this.storeUsers()
        this.joinAdminChannel()
        this.joinUserChannel()
        this.loading = false
      } catch (err) {
        throw err
      }
    },

    initializeApolloClient () {
      apollo.initialize()
    },

    afterLeave () {
      window.scrollTo(0, 0)
    },

    joinUserChannel () {
      this.userChannel = this.$socket.channel(`user:${this.me.id}`, {})
      this.userChannel.join()
        .receive('ok', userId => {
          console.debug(`== Ble medlem av brukerkanal:${this.me.id} med bruker:${userId}`)
          this.loading = false
        })
        .receive('error', resp => { console.error('!! Kunne ikke påmeldes ', resp) })

      this.userChannel.on('token:refresh', jwt => {
        this.$store.commit('users/STORE_TOKEN', jwt)
      })
      this.userChannel.on('progress:show', payload => {
        this.showProgress = true
      })
      this.userChannel.on('progress:hide', payload => {
        this.showProgress = false
        this.progressStatus = {}
      })
      this.userChannel.on('progress:update', payload => {
        let percent = 0
        if (payload.hasOwnProperty('percent')) {
          percent = payload.percent
          if (percent === 100) {
            setTimeout(() => {
              this.$delete(this.progressStatus, payload.key)
            }, 1200)
          }
        }
        if (payload.hasOwnProperty('key')) {
          this.$set(this.progressStatus, payload.key, { content: payload.status, percent: percent })
        } else {
          this.$set(this.progressStatus, 'default', { content: payload.status, percent: percent })
        }
      })
    },

    joinAdminChannel () {
      this.adminChannel = this.$socket.channel('admin', {})
      this.adminChannel.join()
        .receive('ok', userId => {
          console.debug(`== Ble medlem av adminkanal med bruker:${userId}`)
          this.loading = false
        })
        .receive('error', resp => { console.error('!! Kunne ikke påmeldes ', resp) })

      // receive initial presence data from server, sent after join
      this.adminChannel.on('admin:presence_state', state => {
        this.storeLobbyPresences(state)
      })

      // receive 'presence_diff' from server, containing join/leave events
      this.adminChannel.on('presence_diff', diff => {
        this.storeLobbyPresencesDiff(diff)
      })

      // request presences
      this.adminChannel.push('admin:list_presence')
    },

    ...mapActions('users', [
      'storeMe',
      'storeUsers',
      'storeLobbyPresencesDiff',
      'storeLobbyPresences'
    ])
  }
}
</script>
