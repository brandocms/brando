import { 
  Application, 
  Dom, 
  Moonwalk, 
  Events, 
  gsap 
} from '@brandocms/jupiter'

import { Socket } from 'phoenix'
import topbar from 'topbar'

import Navigation from './Navigation'
import Presence from './Presence'
import Toast from './Toast'

import brandoHooks from './hooks'
import initializeLiveSocket from './initializeLiveSocket'
import configureFader from './config/FADER'
import { alertError } from './alerts'

const prmEl = Dom.find('meta[name="prefers_reduced_motion"]')
const PREFERS_REDUCED_MOTION = prmEl ? (prmEl.getAttribute('content') === 'true' ? true : false) : false

if (PREFERS_REDUCED_MOTION) {
  gsap.globalTimeline.timeScale(200)
}

const IS_LOGIN = Dom.find('.auth-login')

topbar.config({ barColors: { 0: 'rgba(5, 39, 82, 1)', 1: '#0047FF' }, shadowColor: 'rgba(0, 0, 0, .2)' })

export default (hooks, enableDebug = true) => {
  let app
  if (IS_LOGIN) {
    const MOONWALK_CONFIG = {
      rootMargin: '0% 0% -10% 0%',
      threshold: 0,
      initialDelay: 100,

      runs: {
        brandoLogin: {
          threshold: 0.0,
          callback: el => {
            const timeline = gsap.timeline()
            gsap.set(['.field-wrapper', '.brando-versioning', '.login-box', '.primary', '.figure-wrapper', '.title'], { opacity: 0 })
            gsap.set('.login-box', { y: 35 })
            gsap.set(['.field-wrapper', '.primary', '.title'], { x: -15 })
            gsap.set('.figure-wrapper', { x: -10 })
            gsap.set('.brando-versioning', { xPercent: -200 })

            timeline
              .to(el, { opacity: 1, duration: 0.5, ease: 'none' })
              .to('.login-box', { y: 0, duration: 0.5, ease: 'power3.out' })
              .to('.login-box', { opacity: 1, duration: 0.5, ease: 'none' }, '<')
              .to(['.title', '.field-wrapper', '.primary'], { x: 0, duration: 0.35, ease: 'circ.out', stagger: 0.1 }, '<0.25')
              .to(['.title', '.field-wrapper', '.primary'], { opacity: 1, duration: 0.35, ease: 'none', stagger: 0.1 }, '<')
              .to('.figure-wrapper', { x: 0, duration: 0.35, ease: 'circ.out' }, '<')
              .to('.figure-wrapper', { opacity: 1, duration: 0.35, ease: 'none' }, '<')
              .to('.brando-versioning', { opacity: 1, ease: 'none' })
              .to('.brando-versioning', { xPercent: 0, ease: 'circ.out' })
          }
        }
      }
    }

    app = new Application({
      breakpointConfig: {
        breakpoints: [
          'iphone',
          'mobile',
          'ipad_portrait',
          'ipad_landscape',
          'desktop_md',
          'desktop_lg',
          'desktop_xl'
        ]
      },
      faderOpts: {
        fadeIn: callback => {
          gsap.set('.fader', { display: 'none' })
          document.body.classList.remove('unloaded')
          callback()
        }
      }
    })

    app.registerCallback(Events.APPLICATION_PRELUDIUM, () => {
      app.moonwalk = new Moonwalk(app, MOONWALK_CONFIG)
    })
  } else {
    app = new Application({
      breakpointConfig: {
        breakpoints: [
          'iphone',
          'mobile',
          'ipad_portrait',
          'ipad_landscape',
          'desktop_md',
          'desktop_lg',
          'desktop_xl'
        ]
      },
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

      app.registerCallback(Events.APPLICATION_READY, () => {
        app.liveSocket = initializeLiveSocket({ ...hooks, ...brandoHooks(app) }, enableDebug)
      })

      window.addEventListener('phx:b:component:remount', () => {
        app.components.forEach(cmp => cmp.remount())
      })

      let topBarScheduled = undefined;
      window.addEventListener('phx:page-loading-start', ({ detail }) => {
        if (!topBarScheduled) {
          topBarScheduled = setTimeout(() => topbar.show(), 200)
        }
      })

      window.addEventListener('phx:page-loading-stop', ({ detail }) => {
        clearTimeout(topBarScheduled)
        topBarScheduled = undefined
        topbar.hide()

        if (detail.kind === 'redirect' && app.reconnected) {
          app.reconnected = false
        }

        if (detail.kind === 'initial' && !app.reconnected) {
          app.navigation.checkFullscreen()
          app.presence.setUrl(detail.to)
        }
      })      

      const $progressWrapper = Dom.find('.progress-wrapper')
      const $progress = Dom.find($progressWrapper, '.progress')
      gsap.set($progressWrapper, { yPercent: -100 })

      app.userSocket = new Socket('/admin/socket', { params: { token: app.userToken } })
      app.userSocket.connect()

      app.userChannel = app.userSocket.channel(`user:${app.userId}`, {})
      app.lobbyChannel = app.userSocket.channel('lobby', {})

      app.lobbyChannel.on('toast', data => {
        app.toast.mutation(data.level, data.payload)
      })

      app.userChannel.on('progress:show', () => {
        gsap.to($progressWrapper, { yPercent: 0, ease: 'circ.out', duration: 0.35 })
      })

      app.userChannel.on('progress:hide', () => {
        gsap.to($progressWrapper, { yPercent: -100, ease: 'circ.in', duration: 0.35 })
      })

      app.userChannel.on('toast', data => {
        app.toast.notification(data.level, data.payload)
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
                keyEl.remove()
                gsap.to($progressWrapper, { height: getHeights() })
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

      app.userChannel.join().receive('ok', params => {
        if (app.vsn) {
          // we've connected before. see if versions match!
          if (app.vsn !== params.vsn) {
            // new version, alert user
            alertError('👀', 'The application was updated while you were logged in. It is recommended to refresh the page, but make sure you have saved your work first.')
          }
        } else {
          app.vsn = params.vsn
        }

        console.debug('==> Joined user_channel')
      })

      app.lobbyChannel.join().receive('ok', () => {
        app.presence.trackIdle()
        console.debug('==> Joined lobby_channel')
      })
    })
  }

  return app
}
