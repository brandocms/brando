<template>
  <div
    v-if="token && ready"
    id="app"
    :class="{ noFocus, 'loaded': !loading, 'fullscreen': fullScreen}">
    <Navigation ref="nav" />
    <Content ref="content" />
  </div>
  <div v-else-if="ready">
    <LoginView />
  </div>
</template>

<script>

import gql from 'graphql-tag'
import { gsap } from 'gsap'

import LoginView from './views/auth/LoginView'
export default {
  components: {
    LoginView
  },

  data () {
    return {
      noFocus: true,
      loading: 1,
      initialized: false,
      ready: false,
      fullScreen: false
    }
  },

  watch: {
    fullscreen (value) {
      if (value) {
        gsap.to('#navigation', { ease: 'power2.in', duration: 0.35, xPercent: '-100' })
        gsap.to('main', { ease: 'power2.in', duration: 0.35, marginLeft: 0 })
      } else {
        gsap.to('#navigation', { ease: 'power2.in', duration: 0.35, xPercent: '0' })
        gsap.to('main', { ease: 'power2.in', duration: 0.35, marginLeft: 370 })
      }
    },

    // me (value) {
    //   if (value && !this.initialized) {
    //     this.initialized = true
    //     this.initializeApp()
    //   }
    // },

    '$route' () {
      if (this.$route.meta.fullScreen) {
        this.fullScreen = true
      } else {
        this.fullScreen = false
      }
    }
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

  async created () {
    console.debug('created <App />')

    document.addEventListener('keydown', e => {
      if (e.keyCode === 9 || e.which === 9) {
        this.noFocus = false
      }
    })

    if (this.$route.meta.fullScreen) {
      this.fullScreen = true
    }

    this.setToken(localStorage.getItem('token'))

    if (this.token) {
      // check if the token is valid — might be old
      let fmData = new FormData()
      fmData.append('jwt', this.token)

      const response = await fetch('/admin/auth/verify', {
        method: 'post',
        body: fmData
      })

      switch (response.status) {
        // case 200:
        //   await this.initializeApp()
        //   break
        case 406:
          this.setToken(null)
          localStorage.removeItem('token')

          // this.$router.push({ name: 'login' })
          window.location = '/admin/login?expired=true?code=406'
          break
        case 401:
          this.setToken(null)
          localStorage.removeItem('token')

          window.location = '/admin/login?expired=true?code=401'
      }
    } else {
      this.loading = 0
      this.ready = true
    }
  },

  methods: {
    setToken (value) {
      this.$apollo.mutate({
        mutation: gql`
          mutation setToken ($value: String!) {
            tokenSet (value: $value) @client
          }
        `,
        variables: {
          value: localStorage.getItem('token')
        }
      })
    },

    async initializeApp () {
      console.log('connectsocket')
      this.connectSocket()
      try {
        this.joinAdminChannel()
        this.joinUserChannel()
      } catch (err) {
        throw err
      }
    },

    toggleFocus () {
      this.noFocus = false
    },

    joinUserChannel () {
      this.userChannel = this.$socket.channel(`user:${this.me.id}`, {})
      this.userChannel.join()
        .receive('ok', userId => {
          console.debug(`== Ble medlem av brukerkanal:${this.me.id} med bruker:${userId}`)
          this.loading = false
        })
        .receive('error', resp => { console.error('!! Kunne ikke påmeldes ', resp) })

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
          this.ready = true
        })
        .receive('error', resp => { console.error('!! Kunne ikke påmeldes ', resp) })

      // receive initial presence data from server, sent after join
      this.adminChannel.on('admin:presence_state', state => {
        // this.storeLobbyPresences(state)
      })

      // receive 'presence_diff' from server, containing join/leave events
      this.adminChannel.on('presence_diff', diff => {
        // this.storeLobbyPresencesDiff(diff)
      })

      // request presences
      this.adminChannel.push('admin:list_presence')
    }
  },

  apollo: {
    token: gql`
      query getToken {
        token @client
      }
    `,

    fullscreen: gql`
      query getFullscreen {
        fullscreen @client
      }
    `,

    me: {
      query: gql`
        query Me {
          me {
            id
            full_name
            email
            avatar {
              focal
              thumb: url(size: "xlarge")
            }
            role
            language
            active
          }
        }
      `,

      update ({ me }) {
        this.$i18n.locale = me.language
        if (!this.initialized) {
          this.initialized = true
          this.initializeApp()
        }
      },

      skip () {
        return !this.token
      }
    },

    identity: {
      query: gql`
        query Identity {
          identity {
            id
            type
            name
            alternate_name
            email
            phone
            address
            zipcode
            city
            country
            description
            title_prefix
            title
            title_postfix

            image {
              thumb: url(size: "original")
              focal
            }

            logo {
              thumb: url(size: "original")
              focal
            }

            links {
              id
              name
              url
            }

            metas {
              id
              key
              value
            }

            configs {
              id
              key
              value
            }

            url
          }
        }
      `,

      skip () {
        return !this.token
      }
    }
  }
}
</script>

<style lang="postcss">
  @europa base;

  @font-face {
    font-family: 'Founders Grotesk';
    src: url('/fonts/FoundersGrotesk-Regular.eot?#iefix') format('embedded-opentype'),  url('/fonts/FoundersGrotesk-Regular.otf')  format('opentype'),
         url('/fonts/FoundersGrotesk-Regular.woff') format('woff'), url('/fonts/FoundersGrotesk-Regular.ttf')  format('truetype'), url('/fonts/FoundersGrotesk-Regular.svg#FoundersGrotesk-Regular') format('svg');
    font-weight: 400;
    font-style: normal;
  }

  @font-face {
    font-family: 'Founders Grotesk';
    src: url('/fonts/FoundersGrotesk-Medium.eot?#iefix') format('embedded-opentype'),  url('/fonts/FoundersGrotesk-Medium.otf')  format('opentype'),
         url('/fonts/FoundersGrotesk-Medium.woff') format('woff'), url('/fonts/FoundersGrotesk-Medium.ttf')  format('truetype'), url('/fonts/FoundersGrotesk-Medium.svg#FoundersGrotesk-Medium') format('svg');
    font-weight: 500;
    font-style: normal;
  }

  @font-face {
    font-family: 'Founders Grotesk';
    src: url('/fonts/FoundersGrotesk-Light.eot?#iefix') format('embedded-opentype'),  url('/fonts/FoundersGrotesk-Light.otf')  format('opentype'),
         url('/fonts/FoundersGrotesk-Light.woff') format('woff'), url('/fonts/FoundersGrotesk-Light.ttf')  format('truetype'), url('/fonts/FoundersGrotesk-Light.svg#FoundersGrotesk-Light') format('svg');
    font-weight: 200;
    font-style: normal;
  }

  html {
    height: 100%;
  }

  body {
    color: theme(colors.dark);
    background-color: theme(colors.peachDarker);
  }

  .float-right {
    float: right;
  }

  .row {
    @row;

    .half {
      @column 8/16;
    }

    .third {
      width: 33%;
    }
  }

  .muted {
    opacity: 0.3;
  }

  #app {
    display: flex;
    min-height: 100%;
    height: 100%;

    &.noFocus {
      a,
      button,
      input,
      label,
      option,
      select,
      textarea {
        outline: none !important;
      }

      button:not(:focus) {
        outline: 0;
      }

      * {
        outline: 0 !important;
      }
    }

    #navigation {
      position: fixed;
      height: 100%;
    }

    main {
      margin-left: 370px;
    }
  }

  .table td.fit, .table th.fit {
    white-space: nowrap;
    width: 1%;
  }

  p:last-of-type {
    margin-bottom: 0 !important;
  }

  h2 {
    @fontsize xl;
  }

  h3 {
    @fontsize lg;
    font-weight: 200;
  }

  .btn-primary {
    width: 100%;
    display: block;
    padding-top: 5px;
    color: theme(colors.dark);
    border: 1px solid theme(colors.dark);
    background-color: transparent;
    height: 60px;
    padding-bottom: 0px;
    min-width: 205px;
    text-align: center;
    transition: background-color 0.25s ease, border-color 0.25s ease;

    &:hover {
      background-color: theme(colors.peach);
    }
  }

  .btn-outline-secondary {
    @fontsize sm;
    width: 100%;
    display: block;
    padding-top: 5px;
    color: theme(colors.dark);
    border: 1px solid theme(colors.dark);
    background-color: transparent;
    height: 40px;
    padding-bottom: 0px;
    text-align: center;
    transition: background-color 0.25s ease, border-color 0.25s ease;

    &:hover {
      background-color: theme(colors.peach);
    }
  }

  .btn-secondary {
    @fontsize base;
    width: 100%;
    display: block;
    padding-top: 5px;
    color: theme(colors.dark);
    border: 1px solid theme(colors.dark);
    background-color: transparent;
    height: 60px;
    padding-bottom: 0px;
    text-align: center;
    transition: background-color 0.25s ease, border-color 0.25s ease;

    + .btn-secondary {
      margin-top: -1px;
    }

    &:hover {
      background-color: theme(colors.peach);
    }
  }

  .btn-outline-primary {
    padding-top: 5px;
    color: #ffffff;
    border: 1px solid theme(colors.blue);
    background-color: theme(colors.blue);
    height: 60px;
    border-radius: 30px;
    padding-bottom: 0px;
    min-width: 205px;
    text-align: center;
    transition: background-color 0.25s ease, border-color 0.25s ease;

    &:hover {
      background-color: theme(colors.dark);
      border-color: theme(colors.dark);
    }
  }

  .cap {
    text-transform: capitalize;
  }

  .thumb {
    @space padding-right 1;
    border-right: 1px solid rgba(0, 0, 0, 0.2);
    img {
      max-width: 100%;
      width: 100%;
      border: 5px solid theme(colors.blue);
    }
  }

  .col-1 {
    @column 1/16;
  }

  .col-2 {
    @column 2/16;
  }

  .col-3 {
    @column 3/16;
  }

  .col-4 {
    @column 4/16;
  }

  .col-5 {
    @column 5/16;
  }

  .col-6 {
    @column 6/16;
  }

  .col-7 {
    @column 7/16;
  }

  .col-8 {
    @column 8/16;
  }

  .col-9 {
    @column 9/16;
  }

  .col-10 {
    @column 10/16;
  }

  .col-11 {
    @column 11/16;
  }

  .col-12 {
    @column 12/16;
  }

  .col-13 {
    @column 13/16;
  }

  .col-14 {
    @column 14/16;
  }

  .col-15 {
    @column 15/16;
  }

  .col-16 {
    @column 16/16;
  }

.list {
  .center {
    margin: 0 auto;
  }

  .flex-v {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
  }

}

.mt-3 {
  margin-top: 25px;
}

.mb-3 {
  margin-bottom: 25px;
}

.circle {
  width: 40px;
  height: 40px;
  border-radius: 20px;
  line-height: 1;
  border: 1px solid theme(colors.dark);
  font-family: theme(typography.families.mono);
  font-size: 14px;
  text-transform: uppercase;
  display: flex;
  justify-content: center;
  align-items: center;

  span {
    color: theme(colors.dark);
  }
}

.text-center {
  text-align: center !important;
}

.badge {
  display: inline-block;
  font-family: theme(typography.families.mono);
  font-size: 14px;
  text-transform: uppercase;
  display: inline-block;
  padding: 3px 5px 2px;
  line-height: 1;
  border: 1px solid theme(colors.blue);
  user-select: none;
  & + .badge {
    margin-left: -1px;
  }
}

.alert-backdrop {
  position: fixed;
  top: 0;
  left: 0;
  width: 100%;
  height: 100%;
  background-color: #000000cf;
  z-index: 10005;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;

  .kprogress {
    z-index: 999999;
    background-color: white;
    padding: 4rem;
    transition: height 0.15s ease-out;

    .kprogress-percent {
      font-size: 2.5rem;
      font-weight: bold;
      margin-bottom: 10px;
    }

    .kprogress-content {
      span {
        animation-name: blink;
        animation-duration: 1.4s;
        animation-iteration-count: infinite;
        animation-fill-mode: both;
      }

      span:nth-child(2) {
        animation-delay: .2s;
      }

      span:nth-child(3) {
        animation-delay: .4s;
      }
    }
  }
}

@keyframes blink {
  0% {
    opacity: .2;
  }

  20% {
    opacity: 1;
  }
  100% {
    opacity: .2;
  }
}

@keyframes vex-pulse {
  0% {
    -moz-box-shadow: inset 0 0 0 300px transparent;
    -webkit-box-shadow: inset 0 0 0 300px transparent;
    box-shadow: inset 0 0 0 300px transparent;
  }

  100% {
    -moz-box-shadow: inset 0 0 0 300px transparent;
    -webkit-box-shadow: inset 0 0 0 300px transparent;
    box-shadow: inset 0 0 0 300px transparent;
  }

  70% {
    -moz-box-shadow: inset 0 0 0 300px rgba(255, 255, 255, 0.25);
    -webkit-box-shadow: inset 0 0 0 300px rgba(255, 255, 255, 0.25);
    box-shadow: inset 0 0 0 300px rgba(255, 255, 255, 0.25);
  }
}

@-webkit-keyframes vex-pulse {
  0% {
    -moz-box-shadow: inset 0 0 0 300px transparent;
    -webkit-box-shadow: inset 0 0 0 300px transparent;
    box-shadow: inset 0 0 0 300px transparent;
  }

  100% {
    -moz-box-shadow: inset 0 0 0 300px transparent;
    -webkit-box-shadow: inset 0 0 0 300px transparent;
    box-shadow: inset 0 0 0 300px transparent;
  }

  70% {
    -moz-box-shadow: inset 0 0 0 300px rgba(255, 255, 255, 0.25);
    -webkit-box-shadow: inset 0 0 0 300px rgba(255, 255, 255, 0.25);
    box-shadow: inset 0 0 0 300px rgba(255, 255, 255, 0.25);
  }
}

@-moz-keyframes vex-pulse {
  0% {
    -moz-box-shadow: inset 0 0 0 300px transparent;
    -webkit-box-shadow: inset 0 0 0 300px transparent;
    box-shadow: inset 0 0 0 300px transparent;
  }

  100% {
    -moz-box-shadow: inset 0 0 0 300px transparent;
    -webkit-box-shadow: inset 0 0 0 300px transparent;
    box-shadow: inset 0 0 0 300px transparent;
  }

  70% {
    -moz-box-shadow: inset 0 0 0 300px rgba(255, 255, 255, 0.25);
    -webkit-box-shadow: inset 0 0 0 300px rgba(255, 255, 255, 0.25);
    box-shadow: inset 0 0 0 300px rgba(255, 255, 255, 0.25);
  }
}

@-ms-keyframes vex-pulse {
  0% {
    -moz-box-shadow: inset 0 0 0 300px transparent;
    -webkit-box-shadow: inset 0 0 0 300px transparent;
    box-shadow: inset 0 0 0 300px transparent;
  }

  100% {
    -moz-box-shadow: inset 0 0 0 300px transparent;
    -webkit-box-shadow: inset 0 0 0 300px transparent;
    box-shadow: inset 0 0 0 300px transparent;
  }

  70% {
    -moz-box-shadow: inset 0 0 0 300px rgba(255, 255, 255, 0.25);
    -webkit-box-shadow: inset 0 0 0 300px rgba(255, 255, 255, 0.25);
    box-shadow: inset 0 0 0 300px rgba(255, 255, 255, 0.25);
  }
}

@-o-keyframes vex-pulse {
  0% {
    -moz-box-shadow: inset 0 0 0 300px transparent;
    -webkit-box-shadow: inset 0 0 0 300px transparent;
    box-shadow: inset 0 0 0 300px transparent;
  }

  100% {
    -moz-box-shadow: inset 0 0 0 300px transparent;
    -webkit-box-shadow: inset 0 0 0 300px transparent;
    box-shadow: inset 0 0 0 300px transparent;
  }

  70% {
    -moz-box-shadow: inset 0 0 0 300px rgba(255, 255, 255, 0.25);
    -webkit-box-shadow: inset 0 0 0 300px rgba(255, 255, 255, 0.25);
    box-shadow: inset 0 0 0 300px rgba(255, 255, 255, 0.25);
  }
}

.vex.vex-theme-kurtz {
  padding-bottom: 160px;
  padding-top: 160px;
  z-index: 100000 !important;
}

.vex-overlay {
  z-index: 9999 !important;
  background-color: theme(colors.blue);
}

.vex.vex-theme-kurtz .vex-content {
  background: #fff;
  border: 2px solid #000;
  color: #000;
  font-family: theme(typography.families.main);
  font-size: 1.1em;
  line-height: 1.5em;
  margin: 0 auto;
  max-width: 100%;
  padding: 2em;
  position: relative;
  width: 400px;
}

.vex.vex-theme-kurtz .vex-content h1,
.vex.vex-theme-kurtz .vex-content h2,
.vex.vex-theme-kurtz .vex-content h3,
.vex.vex-theme-kurtz .vex-content h4,
.vex.vex-theme-kurtz .vex-content h5,
.vex.vex-theme-kurtz .vex-content h6,
.vex.vex-theme-kurtz .vex-content li,
.vex.vex-theme-kurtz .vex-content p,
.vex.vex-theme-kurtz .vex-content ul {
  color: inherit;
}

.vex.vex-theme-kurtz .vex-close {
  cursor: pointer;
  position: absolute;
  right: 0;
  top: 0;
}

.vex.vex-theme-kurtz .vex-close:before {
  color: #000;
  content: "\00D7";
  font-size: 40px;
  font-weight: normal;
  height: 80px;
  line-height: 80px;
  position: absolute;
  right: 3px;
  text-align: center;
  top: 3px;
  width: 80px;
}

.vex.vex-theme-kurtz .vex-close:active:before,
.vex.vex-theme-kurtz .vex-close:hover:before {
  color: #000;
}

.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-message {
  margin-bottom: 1.5em;
}

.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input {
  margin-bottom: 1em;
}

.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="date"],
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="datetime"],
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="datetime-local"],
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="email"],
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="month"],
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="number"],
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="password"],
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="search"],
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="tel"],
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="text"],
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="time"],
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="url"],
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="week"],
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input select,
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input textarea {
  background: #fff;
  border: 2px solid #000;
  font-family: inherit;
  font-size: inherit;
  font-weight: inherit;
  margin: 0 0 0.25em;
  min-height: 2.5em;
  padding: 0.25em 0.67em;
  width: 100%;
}

.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="date"]:focus,
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="datetime"]:focus,
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="datetime-local"]:focus,
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="email"]:focus,
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="month"]:focus,
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="number"]:focus,
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="password"]:focus,
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="search"]:focus,
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="tel"]:focus,
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="text"]:focus,
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="time"]:focus,
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="url"]:focus,
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input input[type="week"]:focus,
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input select:focus,
.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-input textarea:focus {
  border-style: dashed;
  outline: none;
}

.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-buttons {
  *zoom: 1;
  text-align: center;
}

.vex.vex-theme-kurtz .vex-dialog-form .vex-dialog-buttons:after {
  clear: both;
  content: "";
  display: table;
}

.vex.vex-theme-kurtz .vex-dialog-button {
  -moz-border-radius: 0;
  -webkit-border-radius: 0;
  border: 0;
  border-radius: 0;
  float: none;
  font-family: inherit;
  font-size: 0.8em;
  letter-spacing: 0.1em;
  line-height: 1em;
  margin: 0 0.5em;
  padding: 0.75em 2em;
  text-transform: uppercase;
}

.vex.vex-theme-kurtz .vex-dialog-button.vex-last {
  margin-left: 0;
}

.vex.vex-theme-kurtz .vex-dialog-button:focus {
  -moz-animation: vex-pulse 1.1s infinite;
  -ms-animation: vex-pulse 1.1s infinite;
  -o-animation: vex-pulse 1.1s infinite;
  -webkit-animation: vex-pulse 1.1s infinite;
  -webkit-backface-visibility: hidden;
  animation: vex-pulse 1.1s infinite;
  outline: none;
}

@media (max-width: 568px) {
  .vex.vex-theme-kurtz .vex-dialog-button:focus {
    -moz-animation: none;
    -ms-animation: none;
    -o-animation: none;
    -webkit-animation: none;
    -webkit-backface-visibility: hidden;
    animation: none;
  }
}

.dialog-title {
  font-weight: 600;
}

.vex.vex-theme-kurtz .vex-dialog-button.vex-dialog-button-primary {
  background: #000;
  border: 2px solid transparent;
  color: #fff;
}

.vex.vex-theme-kurtz .vex-dialog-button.vex-dialog-button-secondary {
  background: #fff;
  border: 2px solid #000;
  color: #000;
}

.vex-loading-spinner.vex-theme-kurtz {
  height: 2.5em;
  width: 2.5em;
}

.iziToast {
  font-family: theme(typography.families.main);

  > .iziToast-close {
    background: url('data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAQAAADZc7J/AAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAAAmJLR0QAAKqNIzIAAAAJcEhZcwAADdcAAA3XAUIom3gAAAAHdElNRQfgCR4OIQIPSao6AAAAwElEQVRIx72VUQ6EIAwFmz2XB+AConhjzqTJ7JeGKhLYlyx/BGdoBVpjIpMJNjgIZDKTkQHYmYfwmR2AfAqGFBcO2QjXZCd24bEggvd1KBx+xlwoDpYmvnBUUy68DYXD77ESr8WDtYqvxRex7a8oHP4Wo1Mkt5I68Mc+qYqv1h5OsZmZsQ3gj/02h6cO/KEYx29hu3R+VTTwz6D3TymIP1E8RvEiiVdZfEzicxYLiljSxKIqlnW5seitTW6uYnv/Aqh4whX3mEUrAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDE2LTA5LTMwVDE0OjMzOjAyKzAyOjAwl6RMVgAAACV0RVh0ZGF0ZTptb2RpZnkAMjAxNi0wOS0zMFQxNDozMzowMiswMjowMOb59OoAAAAZdEVYdFNvZnR3YXJlAHd3dy5pbmtzY2FwZS5vcmeb7jwaAAAAAElFTkSuQmCC') no-repeat 50% 50%;
  }

  &.iziToast-theme-brando {
    color: white;

    > .iziToast-body .iziToast-message {
      @fontsize base;
    }

    &.iziToast-color-green {
      background-color: theme(colors.blue);

      > .iziToast-body .iziToast-message {
        color: theme(colors.peach);
        margin-top: 3px;
      }
    }

    &.iziToast-color-red {
      background: rgba(255, 0, 0, 0.9);
      border-color: rgba(255, 175, 180, 0.9);

      > .iziToast-body {
        > p {
          color: #fff;
        }
      }
    }

    .iziToast-icon {
      color: #fff;
    }

    .iziToast-icon.ico-error {
      background: url("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAMAAACdt4HsAAAAeFBMVEUAAAD////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////GqOSsAAAAJ3RSTlMA3BsB98QV8uSyWVUFz6RxYwzYvbupmYqAaU1FQTXKv7abj4d1azKNUit3AAACZElEQVRYw7WXaZOCMAyGw30UORRQBLxX/v8/3BkaWjrY2szO5otKfGrzJrEp6Kw6F8f8sI+i/SE/FucKSBaWiT8p5idlaEtnXTB9tKDLLHAvdSatOan3je93k9F2vRF36+mr1a6eH2NFNydoHq/ieU/UXcWjjk9XykdNWq2ywtp4tXL6Wb2T/MqtzzZutsrNyfvA51KoQROhVCjfrnASIRpSVUZiD5v4RbWExjRdJzSmOsZFvzYz59kRSr6V5zE+/QELHkNdb3VRx45HS1b1u+zfkkcbRAZ3qJ9l/A4qefHUDMShJe+6kZKJDD2pLQ9Q4lu+5Q7rz7Plperd7AtQEgIPI6o2dxr2D4GXvxqCiKcn8cD4gxIAEt7/GYkHL16KqeJd0NB4gJbXfgVnzCGJlzGcocCVSLzUvoAj9xJ4NF7/R8gxoVQexc/hgBpSebjPjgPs59cHmYfn7NkDb6wXmUf1I1ygIPPw4gtgCE8yDw8eAop4J/PQcBExjQmZx37MsZB2ZB4cLKQCG5vKYxMWSzMxIg8pNtOyUkvkocEmXGo69mh8FgnxS4yBwMvDrJSNHZB4uC3ayz/YkcIP4lflwVIT+OU07ZSjrbTkZQ6dTPkYubZ8GC/Cqxu6WvJZII93dcCw46GdNqdpTeF/tiMOuDGB9z/NI6NvyWetGPM0g+bVNeovBmamHXWj0nCbEaGeTMN2PWrqd6cM26ZxP2DeJvj+ph/30Zi/GmRbtlK5SptI+nwGGnvH6gUruT+L16MJHF+58rwNIifTV0vM8+hwMeOXAb6Yx0wXT+b999WXfvn+8/X/F7fWzjdTord5AAAAAElFTkSuQmCC") no-repeat 50% 50%;
      background-size: 80%;
    }

    .iziToast-icon.ico-info {
      background: url("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAMAAACdt4HsAAAAflBMVEUAAAD////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////vroaSAAAAKXRSTlMA6PsIvDob+OapavVhWRYPrIry2MxGQ97czsOzpJaMcE0qJQOwVtKjfxCVFeIAAAI3SURBVFjDlJPZsoIwEETnCiGyb8q+qmjl/3/wFmGKwjBROS9QWbtnOqDDGPq4MdMkSc0m7gcDDhF4NRdv8NoL4EcMpzoJglPl/KTDz4WW3IdvXEvxkfIKn7BMZb1bFK4yZFqghZ03jk0nG8N5NBwzx9xU5cxAg8fXi20/hDdC316lcA8o7t16eRuQvW1XGd2d2P8QSHQDDbdIII/9CR3lUF+lbucfJy4WfMS64EJPORnrZxtfc2pjJdnbuags3l04TTtJMXrdTph4Pyg4XAjugAJqMDf5Rf+oXx2/qi4u6nipakIi7CsgiuMSEF9IGKg8heQJKkxIfFSUU/egWSwNrS1fPDtLfon8sZOcYUQml1Qv9a3kfwsEUyJEMgFBKzdV8o3Iw9yAjg1jdLQCV4qbd3no8yD2GugaC3oMbF0NYHCpJYSDhNI5N2DAWB4F4z9Aj/04Cna/x7eVAQ17vRjQZPh+G/kddYv0h49yY4NWNDWMMOMUIRYvlTECmrN8pUAjo5RCMn8KoPmbJ/+Appgnk//Sy90GYBCGgm7IAskQ7D9hFKW4ApB1ei3FSYD9PjGAKygAV+ARFYBH5BsVgG9kkBSAQWKUFYBRZpkUgGVinRWAdUZQDABBQdIcAElDVBUAUUXWHQBZx1gMAGMprM0AsLbVXHsA5trZe93/wp3svQ0YNb/jWV3AIOLsMtlznSNOH7JqjOpDVh7z8qCZR10ftvO4nxeOvPLkpSuvfXnxzKtvXr7j+v8C5ii0e71At7cAAAAASUVORK5CYII=") no-repeat 50% 50%;
      background-size: 85%;
    }

    .iziToast-icon.ico-question {
      background: url("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAABACAQAAAAAYLlVAAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAAAmJLR0QAAKqNIzIAAAAJcEhZcwAADdcAAA3XAUIom3gAAAAHdElNRQfhCQkUEg18vki+AAAETUlEQVRo3s1ZTWhbRxD+VlIuxsLFCYVIIQYVopBDoK5bKDWUBupDMNbJ5FBKg/FBziUQdE9yaC+FHBrwsdCfQ9RTGoLxwWl+DqHEojUFFydxnB9bInZDqOsErBrr6yGvs/ueX97bldTKo4Pe7puZb3Z33s7srIIjMY1jyCEjP6ImvyX8pF64arSHznKC06wzijY5xSKz7YbuYokV2lODsyyxqz3gSY6z6gCuqcpxJluFH+Z8U+D/0jyHoxFUBHgfvsGHIS9WMIUlVFFDFTUAGWSRQRY5HMeBEP6b+Ew9dh/7INd2jGeO59kfKdXP85zbIbfGQVf4sYC3N1hm3lo6zzIbPvk6x+zBk7wQGMEMB5xncIAzAS0XrFySSV72iS1yyBVcdA1x0afrsoUJgdFfY2+z8ADAXl7zz0KcwJiPfZKpVuABgClO+nRG+QIHDdfb4qlWwUXvKW4Z7vi6L4J9vg+vbfCeCeZH2RfOdMOc/HbCA4BvIW6EMQz7XK/ltd+hP+VzR9mgva2YSfyGI17fA7ynnocqeQNFfIJ0oHsdv6CC2+rXGBN6cQdveY3fcVRtmy/HDete+93zy8jA8zV7YkwYMrjHzRddRsCdiVCwwmh6wg9iTNC7Y9XIF1iS7kbUpsvvGEdPuTfSgAEjRpR096x0liPFD/Eqt2NMuBQzB2XhrACAApjFsuQFh9XdGAX70B3oSuNdnMVBaX+sopYxjwVpHFBVACyKTXNoktjD+6Ll8xhenS9MAAkAI/Lux2YNUOs4I413Ypg1SgEAu7kpFvWjaeJe0fJHDGe/cNaZBkekudw8PMA+0fMwlndZeAsJ5KR/qhUDUJCnSiyvRsolkJHGUgvjH8QXDgZopEzKMKDqCKrwEQ4C6MH7GEXC665buLJG8hlQc4LP4paxfJrOqYVYYY2UARfEIazTbgDg2dB98GebzJd54b8L/iWNdLyooeR6CHyZ+6xk0yKxkYg6nEVSUG4VJ9QJ9cxRCxO+9WiOyvgUeexXP1hLGH5nGuBWVtiSp4vqe3VP0UFWI9Wan4Er3v8q7jjPWVtm4FtcQQMrOKO2nOQCM5AyDMi56FDrKHA/1nyppS1ppBpYaE8wciEjGI2AaeM41kI4doDX4XiT3Qm1gevyruCgZg9P8xIv8m1nCzTKq6oiJ9xTMiZ505P5m8cdZ0CnZMVXHVljM7WMBzxpyDxygtdxoCEFTaMIWbZU85UvBjgUMYy0fBaAF8V1Lj9qWQ1aMZ5f4k9r+AGMSkMP1vZoZih6k6sicc5h/OFHM9vDqU/VIU7zJZdYYsKGH4g4nAJMGiXZRds1pVMoZ69RM5vfkbh0qkBhsnS2RLMLilQdL9MBHS9UAh0v1e6CYnXHy/WeeCcvLDwl/9OVze69tPKM+M+v7eJN6OzFpWdEF0ucDbhVNFXadnVrmJFlkVNGTS2M6pzmhMvltfPhnN2B63sVuL7fcNP3D1TSk2ihosPrAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDE3LTA5LTA5VDIwOjE4OjEzKzAyOjAweOR7nQAAACV0RVh0ZGF0ZTptb2RpZnkAMjAxNy0wOS0wOVQyMDoxODoxMyswMjowMAm5wyEAAAAZdEVYdFNvZnR3YXJlAHd3dy5pbmtzY2FwZS5vcmeb7jwaAAAAAElFTkSuQmCC") no-repeat 50% 50%;
      background-size: 85%;
    }

    .iziToast-icon.ico-success {
      background: url("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEAAAABABAMAAABYR2ztAAAAIVBMVEUAAAD////////////////////////////////////////PIev5AAAACnRSTlMApAPhIFn82wgGv8mVtwAAAKVJREFUSMft0LEJAkEARNFFFEw1NFJb8CKjAy1AEOzAxNw+bEEEg6nyFjbY4LOzcBwX7S/gwUxoTdIn+Jbv4Lv8bx446+kB6VsBtK0B+wbMCKxrwL33wOrVeeChX28n7KTOTjgoEu6DRSYAgAAAAkAmAIAAAAIACQIkMkACAAgAIACAyECBKAOJuCagTJwSUCaUAEMAABEBRwAAEQFLbCJgO4bW+AZKGnktR+jAFAAAAABJRU5ErkJggg==") no-repeat 50% 50%;
      background-size: 85%;
    }

    .iziToast-icon.ico-warning {
      background: url("data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAEQAAABECAMAAAAPzWOAAAAAllBMVEUAAAD////+//3+//3+//3///////z+//3+//3+//3////////////9//3////+//39//3///3////////////+//3+//39//3///z+//z+//7///3///3///3///3////////+//3+//3+//3+//z+//3+//7///3///z////////+//79//3///3///z///v+//3///+trXouAAAAMHRSTlMAB+j87RBf+PXiCwQClSPYhkAzJxnx05tSyadzcmxmHRbp5d7Gwrh4TDkvsYt/WkdQzCITAAAB1UlEQVRYw+3XaXKCQBCGYSIIighoxCVqNJrEPfly/8vFImKXduNsf/Mc4K1y7FnwlMLQc/bUbj85R6bA1LXRDICg6RjJcZa7NQYtnLUGTpERSiOXxrOPkv9s30iGKDmtbYir3H7OUHJa2ylAuvZzRvzUfs7Ii/2cgfTt54x82s8ZSM848gJmYtroQzA2jHwA+LkBIEuMGt+QIng1igzlyMrkuP2CyOi47axRaYTL5jhDJehoR+aovC29s3iIyly3Eb+hRCvZo2qsGTnhKr2cLDS+J73GsqBI9W80UCmWWpEuhIjh6ZRGjyNRarjzKGJ2Ou2himCvjHwqI+rTqQdlRH06TZQR9ek0hiqiPp06mV4ke7QPX6ERUZxO8Uo3sqrfhxvoRrCpvXwL/UjR9GRHMIvLgke4d5QbiwhM6JV2YKKF4vIl7XIBkwm4keryJVmvk/TfwcmPwQNkUQuyA2/sYGwnXL7GPu4bW1jYsmevrNj09/MGZMOEPXslQVqO8hqykD17JfPHP/bmo2yGGpdZiH3IZvzZa7B3+IdDjjpjesHJcvbs5dZ/e+cddVoDdvlq7x12Nac+iN7e4R8OXTjp0pw5CGnOLNDEzeBs5gVwFniAO+8f8wvfeXP2hyqnmwAAAABJRU5ErkJggg==") no-repeat 50% 50%;
      background-size: 85%;
    }
  }
}

</style>
