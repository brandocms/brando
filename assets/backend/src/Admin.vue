<template>
  <div
    v-if="token && $root.ready && !loading"
    id="app"
    :class="{ noFocus, 'loaded': !loading, 'fullscreen': fullScreen}">
    <transition
      @appear="toggleMenuAppear">
      <button
        class="toggle-menu"
        @click="toggleFullscreen">
        <template v-if="fullscreen">
          &rarr;
        </template>
        <template v-else>
          &larr;
        </template>
      </button>
    </transition>

    <Navigation
      v-if="me"
      ref="nav" />

    <Content
      ref="content"
      :show-progress="showProgress"
      :progress-status="progressStatus" />

    <LoggedWarnings
      v-if="me && me.role === 'superuser' && loggedWarnings"
      :logged-warnings="loggedWarnings" />

    <transition-group
      v-if="users && me"
      appear
      tag="div"
      class="presences"
      name="user-presences"
      :css="false"
      @beforeEnter="beforeEnterUser"
      @enter="enterUser">
      <a
        v-for="(u, idx) in orderedUsers"
        :key="u.id"
        :data-idx="idx"
        :data-user-status="checkPresence(u.id)"
        class="user-presence">
        <div
          :key="u.id"
          v-popover="u.name"
          class="avatar">
          <img :src="u.avatar ? u.avatar.thumb : '/images/admin/avatar.png'" />
        </div>
      </a>
    </transition-group>

    <portal-target
      name="modals"
      multiple />
  </div>
  <div v-else-if="!loading">
    <router-view class="content" />
  </div>
</template>

<script>

import Vue from 'vue'
import gql from 'graphql-tag'
import { gsap } from 'gsap'
import { Presence } from 'phoenix'
import IdleJs from 'idle-js'

import { localize } from 'vee-validate'
import en from './locales/validator/en.json'
import no from './locales/validator/no.json'

import getCSSVar from './utils/getCSSVar'
import GET_IDENTITY from './gql/identity/IDENTITY_QUERY.graphql'
import GET_ME from './gql/users/ME_QUERY.graphql'

import LoggedWarnings from './components/system/LoggedWarnings'

const GLOBALS = Vue.observable({ me: {}, identity: {}})

export default {
  components: {
    LoggedWarnings
  },

  provide () {
    const userChannel = {}
    const adminChannel = {}
    // const shared = {}
    const rootApollo = {}

    Object.defineProperty(userChannel, 'channel', {
      enumerable: true,
      get: () => this.userChannel
    })

    Object.defineProperty(adminChannel, 'channel', {
      enumerable: true,
      get: () => this.adminChannel
    })

    Object.defineProperty(rootApollo, 'queries', {
      enumerable: true,
      get: () => this.$apollo.queries
    })

    return {
      userChannel,
      adminChannel,
      rootApollo,
      GLOBALS
    }
  },

  data () {
    return {
      lobbyPresences: {},
      showProgress: false,
      progressStatus: {},
      noFocus: true,
      loading: 2,
      fullScreen: false,
      vsn: null,
      $me: null
    }
  },

  computed: {
    orderedUsers () {
      const usrs = [...this.users.entries]
      if (!usrs) {
        return []
      }

      return usrs.sort((a, b) => {
        if (a.id === this.me.id) {
          return -1
        }
        if (this.isOnline(a.id) && this.isOnline(b.id)) {
          return a.name.localeCompare(b.name)
        }
        if (this.isOnline(a.id) && !this.isOnline(b.id)) {
          return -1
        }
        if (!this.isOnline(a.id) && this.isOnline(b.id)) {
          return 1
        }
        return a.name.localeCompare(b.name)
      })
    }
  },

  watch: {
    loading (value) {},

    fullscreen (value) {
      const main = document.querySelector('main')
      const navigation = document.querySelector('#navigation')

      if (value) {
        if (this.$refs.nav) {
          gsap.to(navigation, { ease: 'power2.in', duration: 0.35, xPercent: '-100' })
          gsap.to(main, { ease: 'power2.in', duration: 0.35, marginLeft: 0 })
        }
      } else {
        if (this.$refs.nav) {
          const marginLeft = getCSSVar(main, '--main-margin-left')
          gsap.to(navigation, { ease: 'power2.in', duration: 0.35, xPercent: '0' })
          gsap.to(main, { ease: 'power2.in', duration: 0.35, marginLeft })
        }
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

  created () {
    this.$root.ready = false
    this.$root.initialized = false

    this.listenForTabs()
    this.checkFullscreen()
    this.checkToken()
  },

  methods: {
    listenForTabs () {
      document.addEventListener('keydown', e => {
        if (e.keyCode === 9 || e.which === 9) {
          this.noFocus = false
        }
      })
    },

    checkFullscreen () {
      if (this.$route.meta.fullScreen) {
        this.fullScreen = true
      }
    },

    async checkToken () {
      const token = localStorage.getItem('token')
      await this.setToken(token)

      if (token) {
        // check if the token is valid — might be old
        const fmData = new FormData()
        fmData.append('jwt', this.token)

        try {
          const response = await fetch('/admin/auth/verify', {
            method: 'post',
            body: fmData
          })

          switch (response.status) {
            case 200: {
              this.$root.ready = true
              const responseBody = await response.json()
              this.$ability.update(responseBody.rules)
              break
            }
            case 406: {
              this.setToken(null)
              localStorage.removeItem('token')
              this.loading = 0
              this.$router.push({ name: 'logout' })
              break
            }
            case 401: {
              this.setToken(null)
              localStorage.removeItem('token')
              this.loading = 0
              this.$router.push({ name: 'logout' })
              break
            }
          }
        } catch (e) {
          this.setToken(null)
          localStorage.removeItem('token')
          this.loading = 0
          this.$router.push({ name: 'logout' })
        }
      } else {
        this.loading = 0
      }
    },

    toggleMenuAppear (el) {
      gsap.to(el, { duration: 1, opacity: 1, delay: 1.8, ease: 'sine.in' })
    },

    async setToken (value) {
      await this.$apollo.mutate({
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

    async initializeApp (me) {
      this.connectSocket().then(() => {
        this.joinAdminChannel(me)
        this.joinUserChannel(me)
        this.trackIdle()
      })
    },

    trackIdle () {
      /**
       * Add idle checker
      */

      this.idle = new IdleJs({
        idle: 30000, // idle time in ms
        events: ['mousemove', 'keydown', 'mousedown', 'touchstart'], // events that will trigger the idle resetter
        onIdle: () => { this.setActive(false) },
        onActive: () => { this.setActive(true) },
        onHide: () => { this.setActive(false) },
        onShow: () => { this.setActive(true) },
        keepTracking: true,
        startAtIdle: false
      })

      this.idle.start()
    },

    setActive (status) {
      if (this.adminChannel) {
        this.adminChannel.push('user:state', { active: status })
      }
    },

    toggleFocus () {
      this.noFocus = false
    },

    joinUserChannel (me) {
      this.userChannel = this.$socket.channel(`user:${me.id}`, {})
      this.userChannel.join()
        .receive('ok', ({ user_id: userId, vsn }) => {
          console.debug(`==> Joined user_channel:${me.id} with user:${userId} —— vsn: ${vsn}`)

          if (this.vsn) {
            // we've connected before. see if versions match!
            if (this.vsn !== vsn) {
              // new version, alert user
              this.$alerts.alertError('👀', this.$t('application-updated'))
            }
          } else {
            this.vsn = vsn
          }
        })
        .receive('error', resp => { console.error('!! Failed to join ', resp) })

      this.userChannel.on('progress:show', payload => {
        this.showProgress = true
      })

      this.userChannel.on('progress:hide', payload => {
        this.showProgress = false
        this.progressStatus = {}
      })

      this.userChannel.on('progress:update', payload => {
        let percent = 0
        if (Object.prototype.hasOwnProperty.call(payload, 'percent')) {
          percent = payload.percent
          if (percent === 100) {
            setTimeout(() => {
              this.$delete(this.progressStatus, payload.key)
            }, 1200)
          }
        }
        if (Object.prototype.hasOwnProperty.call(payload, 'key')) {
          this.$set(this.progressStatus, payload.key, { content: payload.status, percent: percent })
        } else {
          this.$set(this.progressStatus, 'default', { content: payload.status, percent: percent })
        }
      })
    },

    joinAdminChannel () {
      this.adminChannel = this.$socket.channel('admin', {})

      // receive initial presence data from server, sent after join
      this.adminChannel.on('admin:presence_state', state => {
        this.storeLobbyPresences(state)
      })

      // receive 'presence_diff' from server, containing join/leave events
      this.adminChannel.on('presence_diff', diff => {
        this.storeLobbyPresencesDiff(diff)
      })

      this.adminChannel.join()
        .receive('ok', userId => {
          console.debug(`==> Joined admin channel with user:${userId}`)
          // request presences
          this.adminChannel.push('admin:list_presence', {})
          this.loading = 0
        })
        .receive('error', resp => { console.error('!! Failed to join ', resp) })

      this.adminChannel.on('notifications:mutation', payload => {
        if (this.me.config.showMutationNotifications) {
          this.$toast.show({
            title: payload.user.name,
            message: `${payload.action} [${payload.identifier.type}#<strong>${payload.identifier.id}</strong>] &raquo; "${payload.identifier.title}"`,
            theme: 'mutations',
            displayMode: 2,
            position: 'bottomRight',
            close: false,
            progressBar: false
          })
        }
      })
    },

    storeLobbyPresences (state) {
      const lobbyPresences = Presence.syncState(this.lobbyPresences, state)
      this.lobbyPresences = lobbyPresences
    },

    storeLobbyPresencesDiff (diff) {
      const lobbyPresences = Presence.syncDiff(this.lobbyPresences, diff)
      this.lobbyPresences = lobbyPresences
    },

    toggleFullscreen () {
      this.$apollo.mutate({
        mutation: gql`
          mutation setFullscreen ($value: String!) {
            fullscreenSet (value: $value) @client
          }
        `,
        variables: {
          value: !this.fullscreen
        }
      })
    },

    beforeEnterUser (el) {
      gsap.set(el, { yPercent: 125 })
    },

    enterUser (el, done) {
      gsap.to(el, { delay: 3 + el.dataset.idx * 0.2, yPercent: 0, ease: 'power2.out', onComplete: done })
    },

    checkPresence (userId) {
      if (userId in this.lobbyPresences) {
        // user is online. check if idle
        const isActive = this.lobbyPresences[userId].metas.find(m => m.active === true)
        return isActive ? 'online' : 'idle'
      }
      return 'offline'
    },

    isOnline (userId) {
      return userId in this.lobbyPresences
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
      query: GET_ME,
      fetchPolicy: 'no-cache',

      update ({ me }) {
        if (!this.$root.initialized && me) {
          this.$i18n.locale = me.language
          this.$root.$i18n.locale = me.language
          localize(me.language, me.language === 'no' ? no : en)
          this.$root.initialized = true

          this.initializeApp(me)
        }
        GLOBALS.me = me
        return me
      },

      skip () {
        return !this.$root.ready || !this.token
      }
    },

    identity: {
      query: GET_IDENTITY,

      update ({ identity }) {
        GLOBALS.identity = identity
        return identity
      },

      skip () {
        return !this.$root.ready || !this.token
      }
    },

    loggedWarnings: {
      query: gql`
        query LoggedWarnings {
          loggedWarnings {
            msg
          }
        }
      `,
      skip () {
        return !this.$root.ready || !this.token
      }
    },

    users: {
      query: gql`
        query Users {
          users {
            entries {
              id
              name
              avatar {
                thumb: url(size: "thumb")
              }
            }
          }
        }
      `,
      skip () {
        return !this.$root.ready || !this.token
      }
    }
  }
}
</script>

<i18n>
  {
    "en": {
      "application-updated": "The application was updated while you were logged in. It is recommended to refresh the page, but make sure you have saved your work first.",
      "refresh": "Refresh app"
    },
    "no": {
      "application-updated": "Applikasjonen ble oppdatert mens du var innlogget. Det anbefales å laste inn siden på nytt, men pass på at du har lagret eventuelle endringer først!",
      "refresh": "Last på nytt"
    }
  }
</i18n>

<style lang="postcss">
  @europa base;

  @font-face {
    font-family: 'Main';
    src: url('/fonts/Regular.woff2') format('woff2');
    font-weight: 400;
    font-style: normal;
  }

  @font-face {
    font-family: 'Main';
    src: url('/fonts/Bold.woff2') format('woff2');
    font-weight: 500;
    font-style: normal;
  }

  @font-face {
    font-family: 'Main';
    src: url('/fonts/Light.woff2') format('woff2');
    font-weight: 200;
    font-style: normal;
  }

  @font-face {
    font-family: 'Mono';
    src: url('/fonts/Mono.woff2') format('woff2');
    font-weight: 400;
    font-style: normal;
  }

  .avatar img {
    vertical-align: baseline;
  }

  .tooltip {
    font-size: 12px;
    display: block !important;
    z-index: 10000;

    .tooltip-inner {
      @color fg peach;
      @color bg dark;
      border-radius: 12px;
      padding: 5px 9px 5px;
    }

    .tooltip-arrow {
      width: 0;
      height: 0;
      border-style: solid;
      position: absolute;
      margin: 5px;
      border-color: theme(colors.dark);
      z-index: 1;
    }

    &[x-placement^="top"] {
      margin-bottom: 5px;

      .tooltip-arrow {
        border-width: 5px 5px 0 5px;
        border-left-color: transparent !important;
        border-right-color: transparent !important;
        border-bottom-color: transparent !important;
        bottom: -5px;
        left: calc(50% - 5px);
        margin-top: 0;
        margin-bottom: 0;
      }
    }

    &[x-placement^="bottom"] {
      margin-top: 5px;

      .tooltip-arrow {
        border-width: 0 5px 5px 5px;
        border-left-color: transparent !important;
        border-right-color: transparent !important;
        border-top-color: transparent !important;
        top: -5px;
        left: calc(50% - 5px);
        margin-top: 0;
        margin-bottom: 0;
      }
    }

    &[x-placement^="right"] {
      margin-left: 5px;

      .tooltip-arrow {
        border-width: 5px 5px 5px 0;
        border-left-color: transparent !important;
        border-top-color: transparent !important;
        border-bottom-color: transparent !important;
        left: -5px;
        top: calc(50% - 5px);
        margin-left: 0;
        margin-right: 0;
      }
    }

    &[x-placement^="left"] {
      margin-right: 5px;

      .tooltip-arrow {
        border-width: 5px 0 5px 5px;
        border-top-color: transparent !important;
        border-right-color: transparent !important;
        border-bottom-color: transparent !important;
        right: -5px;
        top: calc(50% - 5px);
        margin-left: 0;
        margin-right: 0;
      }
    }

    &.popover {
      .popover-inner {
        background: #ffffff;
        color: black;
        padding: 24px;
        border-radius: 5px;
        box-shadow: 0 5px 30px rgba(black, .1);
      }

      .popover-arrow {
        border-color: theme(colors.villain.popover);
      }
    }

    &[aria-hidden='true'] {
      visibility: hidden;
      opacity: 0;
      transition: opacity .15s, visibility .15s;
    }

    &[aria-hidden='false'] {
      visibility: visible;
      opacity: 1;
      transition: opacity .15s;
    }
  }

  .monospace {
    @font mono;
  }

  .presences {
    display: flex;
    flex-wrap: wrap;
    flex-direction: row;
    position: fixed;
    left: 5px;
    bottom: 5px;
    width: auto;
  }

  .user-presence {
    display: block;
    margin-right: 5px;
    margin-top: 5px;
    &:last-of-type {
      margin-right: 0;
    }

    > .avatar {
      position: relative;
      display: inline-block;
      width: 30px;
      height: 30px;
      border: 1px solid theme(colors.dark);
      border-radius: 50%;

      &:after {
        content: " ";
        border-radius: 50%;
        border: 1px solid #ffffff;
        top: -2px;
        right: 0;
        width: 10px;
        height: 10px;
        position: absolute;
        opacity: 0;
        background-color: theme(colors.status.published);
        transition: opacity 1s ease, background-color 2s ease;
      }

      img {
        border-radius: 30px;
      }
    }

    &[data-user-status="offline"] {
      > .avatar {
        img {
          filter: grayscale(100%);
          cursor: pointer;
          transition: all 1.5s ease;
          opacity: .35;
        }
      }
    }

    &[data-user-status="online"] {
      > .avatar {
        img {
          filter: grayscale(0%);
          cursor: pointer;
          transition: all 1.5s ease;
          opacity: 1;
        }

        &:after {
          background-color: theme(colors.status.published);
          opacity: 1;
          transition: opacity 1s ease, background-color 2s ease;
        }
      }
    }

    &[data-user-status="idle"] {
      > .avatar {
        img {
          filter: grayscale(0%);
          cursor: pointer;
          transition: all 1.5s ease;
          opacity: 1;
        }

        &:after {
          background-color: theme(colors.status.pending);
          opacity: 1;
          transition: opacity 1s ease, background-color 2s ease;
        }
      }
    }
  }

  .justify-end {
    display: flex;
    justify-content: flex-end;
  }

  .fade-enter-active, .fade-leave-active {
    transition: opacity 0.35s;
  }

  .fadefast-enter-active, .fadefast-leave-active {
    transition: opacity 0.15s;
  }

  .fadefast-enter, .fadefast-leave-to {
    opacity: 0;
  }

  .fade-move-move {
    transition: transform 0.25s ease-in;
  }

  strong {
    font-weight: 500;
  }

  .no-entries {
    @fontsize base;
    background-color: #0000000d;
    margin-top: 25px;
    margin-bottom: 25px;
    padding: 1rem;
  }

  .drop {
    overflow: hidden;
    svg {
      pointer-events: none;
    }
  }

  html {
    line-height: 1.35;
    height: 100%;
    font-feature-settings: "kern" 1, "liga" 1;
    font-kerning: normal;
  }

  body {
    color: theme(colors.dark);
    background-color: theme(colors.dark);
  }

  .main-content .circle-dropdown.wrapper {
    justify-content: flex-end;
    margin-right: 1vw;
  }

  .float-right {
    float: right;
  }

  .text-mono {
    font-family: theme(typography.families.mono);
  }

  .row {
    @row;

    @responsive <=ipad_landscape {
      flex-wrap: wrap;
      > * {
        margin-left: 0 !important;
      }
    }

    &.baseline {
      align-items: baseline;
    }

    .sized {
      @column 8/16 desktop_xl;
      @column 10/16 desktop_lg;
      @column 10/16 desktop_md;
      @column 16/16 <=ipad_landscape;
    }

    .sized + .half {
      @column 8/16 desktop_xl;
      @column 6/16 desktop_lg;
      @column 6/16 desktop_md;
      @column 16/16 <=ipad_landscape;
    }

    .w50, .half {
      @column 8/16 >=desktop_md;
    }

    .third, .w33 {
      width: 33%;
    }

    .w75 {
      width: 75%;
    }
  }

  .half {
    width: 50%;

    &.shaded {
      background-color: #fafafa;
      padding: 1rem;
    }
  }

  .third {
    width: 33%;
  }

  .toggle-menu {
    @fontsize xs/1;
    border: 1px solid theme(colors.dark);
    width: 50px;
    height: 50px;
    position: fixed;
    top: -25px;
    left: -25px;
    border-radius: 25px;
    z-index: 1;
    text-align: right;
    padding-top: 5px;
    padding-right: 5px;
    opacity: 0;
    transform: rotateZ(45deg);
    transform-origin: center;

    &:hover {
      background-color: theme(colors.dark);
      color: theme(colors.peach);
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
      @responsive desktop_xl { --main-margin-left: 370px }
      @responsive desktop_lg { --main-margin-left: 370px }
      @responsive desktop_md { --main-margin-left: 330px }
      @responsive ipad_landscape { --main-margin-left: 330px }
      @responsive ipad_portrait { --main-margin-left: 0 }
      @responsive mobile { --main-margin-left: 0 }
      @responsive iphone { --main-margin-left: 0 }

      margin-left: var(--main-margin-left);
    }
  }

  .table td.fit, .table th.fit {
    white-space: nowrap;
    width: 1%;
  }

  table.table-bordered {
    td {
      border: 1px solid #dee2e6;
      vertical-align: middle;
      padding: 0.75rem;
      position: relative;
    }
  }

  p:last-of-type {
    margin-bottom: 0 !important;
  }

  .clearfix {
    &::after {
      display: block;
      content: "";
      clear: both;
    }
  }

  h1 {
    @fontsize h1;
    @space margin-bottom 10px;
    line-height: 1.05 !important;
    font-feature-settings: 'kern', 'liga', 'dlig', 'hlig', 'cswh';
  }

  h2 {
    @fontsize h2;
  }

  h3 {
    @fontsize h3;
    font-weight: 200;
  }

  .pos-relative {
    position: relative;
  }

  .btn-primary {
    width: 100%;
    display: block;
    padding-top: 5px;
    color: theme(colors.dark);
    border: 1px solid theme(colors.dark);
    background-color: transparent;
    height: 60px;
    padding-bottom: 8px;
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
    padding-bottom: 5px;
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
    padding-bottom: 5px;
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
    color: theme(colors.dark);
    border: 1px solid theme(colors.dark);
    background-color: #ffffff;
    height: 60px;
    border-radius: 30px;
    padding-bottom: 5px;
    min-width: 205px;
    text-align: center;
    transition: background-color 0.25s ease, border-color 0.25s ease;

    &:hover {
      background-color: theme(colors.dark);
      border-color: theme(colors.dark);
      color: theme(colors.peach);
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
      border: 5px solid theme(colors.peachDarkest);
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

  .flex-h {
    display: flex;
    flex-direction: row;
    align-items: center;
    justify-content: space-between;
  }
}

.flex-v {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
}

.flex-h {
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: space-between;
  flex-wrap: wrap;
  &.jc-none {
   justify-content: unset;
  }
}

.fit {
  white-space: nowrap;
  width: 1%;
}

.mt-2 {
  margin-top: 15px;
}

.mt-3 {
  margin-top: 25px;
}

.mb-1 {
  margin-bottom: 7px !important;
}

.mb-2 {
  margin-bottom: 15px !important;
}

.mb-3 {
  margin-bottom: 25px;
}

.mt-40 {
  margin-top: 40px;
}

.mb-xs {
  @space margin-bottom xs;
}

.mb-sm {
  @space margin-bottom sm;
}

.mb-md {
  @space margin-bottom md;
}

.ml-2xs {
  @space margin-left xs/2;
}

.ml-xs {
  @space margin-left xs;
}

.ml-sm {
  @space margin-left sm;
}

.ml-md {
  @space margin-left md;
}

.mr-1 {
  margin-right: 5px;
}

.mb-2 {
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
  user-select: none;

  &.large {
    width: 60px;
    height: 60px;
    border-radius: 60px;
  }

  &.small {
    width: 25px;
    height: 25px;
    border-radius: 25px;
    font-size: 10px;
  }

  span {
    color: theme(colors.dark);
  }
}

.text-center {
  text-align: center !important;
}

.text-small {
  @fontsize sm;
}

.badge {
  display: inline-block;
  font-family: theme(typography.families.mono);
  font-size: 12px;
  text-transform: uppercase;
  display: inline-block;
  padding: 5px 8px 4px;
  line-height: 1;
  border: 1px solid theme(colors.dark);
  border-radius: 15px;
  user-select: none;

  & + .badge {
    margin-left: -1px;
  }

  &.large {
    font-size: 22px;
    transform: translateY(-4px);
    margin-left: 5px;
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
  background-color: rgba(0, 71, 255, 0.85);
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
  width: 550px;
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

  a {
    border-bottom: 2px solid blue;
  }
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
  border: 0;
  border-radius: 0;
  float: none;
  font-family: inherit;
  line-height: 1em;
  border: 0;
  border-radius: 0;
  float: none;
  font-family: inherit;
  line-height: 1em;
  margin: 0 0.5em;
  padding: 0.75em 1em;
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
  font-weight: 500;
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
  border-radius: 0;

  &.iziToast-theme-small-error {
    background-color: #310d0d;
    border-radius: 15px;
    padding: 0;
    min-height: 0;

    > .iziToast-body {
      padding: 0;
      min-height: 25px;
      margin: 0 0 0 12px;

      .iziToast-texts {
        margin: 6px 0 0 0;
      }

      .iziToast-title {
        color: white;
        margin-right: 7px !important;
        font-size: 11px;
      }

      .iziToast-message {
        @font mono;
        color: #eee;
        font-size: 9px;
      }
    }
  }

  &.iziToast-theme-small-success {
    background-color: #1e3d06;
    border-radius: 15px;
    padding: 0;
    min-height: 0;

    > .iziToast-body {
      padding: 0;
      min-height: 25px;
      margin: 0 0 0 12px;

      .iziToast-texts {
        margin: 6px 0 0 0;
      }

      .iziToast-title {
        color: white;
        margin-right: 7px !important;
        font-size: 11px;
      }

      .iziToast-message {
        @font mono;
        color: #eee;
        font-size: 9px;
      }
    }
  }

  &.iziToast-theme-mutations {
    @color bg dark;
    border-radius: 15px;
    padding: 0;
    min-height: 0;

    > .iziToast-body {
      padding: 0;
      min-height: 25px;
      margin: 0 0 0 12px;

      .iziToast-texts {
        margin: 6px 0 0 0;
      }

      .iziToast-title {
        @color fg peach;
        margin-right: 7px !important;
        font-size: 11px;
      }

      .iziToast-message {
        @font mono;
        @color fg peachDarker;
        font-size: 9px;
      }
    }
  }

  &:after {
    box-shadow: none;
    border-radius: 0;
  }

  > .iziToast-close {
    background: url('data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAACAAAAAgCAQAAADZc7J/AAAABGdBTUEAALGPC/xhBQAAACBjSFJNAAB6JgAAgIQAAPoAAACA6AAAdTAAAOpgAAA6mAAAF3CculE8AAAAAmJLR0QAAKqNIzIAAAAJcEhZcwAADdcAAA3XAUIom3gAAAAHdElNRQfgCR4OIQIPSao6AAAAwElEQVRIx72VUQ6EIAwFmz2XB+AConhjzqTJ7JeGKhLYlyx/BGdoBVpjIpMJNjgIZDKTkQHYmYfwmR2AfAqGFBcO2QjXZCd24bEggvd1KBx+xlwoDpYmvnBUUy68DYXD77ESr8WDtYqvxRex7a8oHP4Wo1Mkt5I68Mc+qYqv1h5OsZmZsQ3gj/02h6cO/KEYx29hu3R+VTTwz6D3TymIP1E8RvEiiVdZfEzicxYLiljSxKIqlnW5seitTW6uYnv/Aqh4whX3mEUrAAAAJXRFWHRkYXRlOmNyZWF0ZQAyMDE2LTA5LTMwVDE0OjMzOjAyKzAyOjAwl6RMVgAAACV0RVh0ZGF0ZTptb2RpZnkAMjAxNi0wOS0zMFQxNDozMzowMiswMjowMOb59OoAAAAZdEVYdFNvZnR3YXJlAHd3dy5pbmtzY2FwZS5vcmeb7jwaAAAAAElFTkSuQmCC') no-repeat 50% 50%;
    background-size: 12px;
  }

  &.iziToast-theme-brando {
    @color fg peach;

    > .iziToast-body .iziToast-message {
      @fontsize base;
      margin-left: 5px;
    }

    &.iziToast-color-green {
      @color bg blue;

      > .iziToast-body .iziToast-message {
        @color fg peach;
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
      @color fg peach;
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

input::-webkit-input-placeholder {
  @font main;
  @fontsize base;
}
input:-ms-input-placeholder {
  @font main;
  @fontsize base;
}
input:-moz-placeholder {
  @font main;
  @fontsize base;
}
input::-moz-placeholder {
  @font main;
  @fontsize base;
}

.avatar-sm {
  min-width: auto;
  width: 150px;
}

.avatar-xs {
  min-width: auto;
  width: 75px;
}

</style>
