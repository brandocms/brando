import { 
  Application, 
  Dom, 
  Moonwalk, 
  Events, 
  gsap 
} from '@brandocms/jupiter'

import { Socket } from 'phoenix'
import NProgress from 'nprogress'

import Navigation from './Navigation'
import Presence from './Presence'
import Toast from './Toast'

import configureBreakpoints from './config/BREAKPOINTS'
import configureFader from './config/FADER'
import configureMoonwalk from './config/MOONWALK'

const PREFERS_REDUCED_MOTION = Dom.find('meta[name="prefers_reduced_motion"]').getAttribute('content')

if (PREFERS_REDUCED_MOTION) {
  gsap.globalTimeline.timeScale(200)
}

export default () => {
  const app = new Application({
    breakpointConfig: configureBreakpoints(),
    faderOpts: configureFader()
  })

  app.components = []
  app.reconnected = false
  app.disconnected = false
  app.userId = Dom.find('meta[name="user_id"]').getAttribute('content')
  app.userToken = Dom.find('meta[name="user_token"]').getAttribute('content')

  app.registerCallback(Events.APPLICATION_PRELUDIUM, () => {
    app.navigation = new Navigation(app)
    app.presence = new Presence(app)
    app.toast = new Toast(app)

    window.addEventListener('phx:hook:b:component:remount', () => {
      app.components.forEach(cmp => cmp.remount())
    })

    // Show progress bar on live navigation and form submits
    window.addEventListener('phx:page-loading-start', ({ detail }) => {
      NProgress.start()

      if ((detail.kind === 'initial' || detail.kind === 'redirect') && !app.reconnected) {
        const $main = Dom.find('main .content')
        gsap.to($main, { opacity: 0 })
      }
    })

    window.addEventListener('phx:page-loading-stop', ({ detail }) => {
      NProgress.done()

      if (detail.kind === 'redirect' && app.reconnected) {
        app.reconnected = false
      }

      if (detail.kind === 'initial' && !app.reconnected) {
        const $main = Dom.find('main .content')
        app.moonwalk = new Moonwalk(app, configureMoonwalk(), $main)
        app.navigation.checkFullscreen()
        gsap.to($main, { clearProps: 'opacity' })
        app.moonwalk.ready()
      }
    })

    const $progressWrapper = Dom.find('.progress-wrapper')
    const $progress = Dom.find($progressWrapper, '.progress')
    gsap.set($progressWrapper, { yPercent: -100 })

    app.userSocket = new Socket('/admin/socket', { params: { token: app.userToken } })
    app.userSocket.connect()

    app.userChannel = app.userSocket.channel(`user:${app.userId}`, {})
    app.lobbyChannel = app.userSocket.channel('lobby', {})

    app.userChannel.on('progress:show', () => {
      gsap.to($progressWrapper, { yPercent: 0, ease: 'circ.out', duration: 0.35 })
    })

    app.userChannel.on('progress:hide', () => {
      gsap.to($progressWrapper, { yPercent: -100, ease: 'circ.in', duration: 0.35 })
    })

    app.userChannel.on('toast', data => {
      app.toast.notification(data.level, data.payload)
    })

    app.lobbyChannel.on('toast', data => {
      app.toast.mutation(data.level, data.payload)
    })

    const getHeights = () => {
      const progressItems = Dom.all('.progress-item')

      if (!progressItems.length) {
        return 0
      }

      let height = 0

      progressItems.forEach(item => {
        height += item.clientHeight
      })

      return height
    }

    app.userChannel.on('progress:update', ({ status, content: { key, filename, percent } }) => {
      const keyEl = Dom.find(`[data-progress-key="${key}"]`)

      if (keyEl) {
        const filenameEl = Dom.find(keyEl, '.filename')
        const descriptionEl = Dom.find(keyEl, '.description')
        const percentEl = Dom.find(keyEl, '.percent')

        filenameEl.innerHTML = filename
        descriptionEl.innerHTML = status
        percentEl.innerHTML = `${percent}%`

        if (parseInt(percent) === 100) {
          const tl = gsap.timeline()

          tl.to(keyEl, { opacity: 0 })
            .to(keyEl, { height: 0 })
            .call(() => {
              setTimeout(() => {
                keyEl.remove()
                gsap.to($progressWrapper, { height: getHeights() })
              }, 1000)
            })

        }
      } else {
        const updateProgress = document.createRange().createContextualFragment(`
        <div class="progress-item" data-progress-key="${key}">
          <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" width="16" height="16"><path fill="none" d="M0 0h24v24H0z"/><path d="M18.364 5.636L16.95 7.05A7 7 0 1 0 19 12h2a9 9 0 1 1-2.636-6.364z"/></svg>
          <div class="filename">
            ${filename}
          </div>
          <div class="description">
            ${status}
          </div>
          <div class="percent">
            ${percent}%
          </div>
        </div>          
        `)
        $progress.append(updateProgress)
        const keyEl = Dom.find(`[data-progress-key="${key}"]`)
        gsap.set(keyEl, { opacity: 0 })
        gsap.to(keyEl, { opacity: 1, duration: 0.45 })
      }

      gsap.to($progressWrapper, { height: getHeights() })
    })

    app.userChannel.join().receive('ok', () => {
      console.debug('==> Joined user_channel')
    })

    app.lobbyChannel.join().receive('ok', () => {
      console.debug('==> Joined lobby_channel')
    })
  })

  return app
}