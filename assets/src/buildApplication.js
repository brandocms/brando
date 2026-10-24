import { Application, Dom, Events } from '@brandocms/jupiter'

import { Socket } from 'phoenix'
import topbar from './topbar'

import Presence from './Presence'
import Toast from './Toast'

import brandoHooks from './hooks'
import initializeLiveSocket from './initializeLiveSocket'
import installUICommands from './uiCommands'
import installFloatingDropdowns from './floatingDropdowns'
import installOpeningRows from './openingRow'
import installTooltips from './tooltips'
import installShortcuts from './shortcuts'
import installConfirm from './confirm'
import configureFader from './config/FADER'
import { alertError } from './alerts'
import { animate, ease, set } from './motion'
import installAuthMotion from './authMotion'

topbar.config({
  barThickness: 1,
  // A canvas gradient cannot read custom properties: these are --brando-ink
  // and --brando-accent from css/tokens.css.
  barColors: { 0: '#272b2a', 1: '#254e3f' },
  shadowColor: 'rgba(0, 0, 0, .2)',
})

export default (hooks, enableDebug = false) => {
  let app

  app = new Application({
    breakpointConfig: {
      breakpoints: [
        'iphone',
        'mobile',
        'ipad_portrait',
        'ipad_landscape',
        'desktop_md',
        'desktop_lg',
        'desktop_xl',
      ],
    },
    faderOpts: configureFader(),
  })

  app.components = []
  app.reconnected = false
  app.disconnected = false
  app.userId = null
  app.userToken = null

  const metaUserId = Dom.find('meta[name="user_id"]')
  const metaUserToken = Dom.find('meta[name="user_token"]')

  if (metaUserId) {
    app.userId = metaUserId.getAttribute('content')
  }

  if (metaUserToken) {
    app.userToken = metaUserToken.getAttribute('content')
  }

  app.registerCallback(Events.APPLICATION_PRELUDIUM, () => {
    app.presence = new Presence(app)
    app.toast = new Toast(app)
    // The login screen starts hidden by a stylesheet rule (see auth.html.heex),
    // not by an inline style set here — LiveView's connected mount patch would
    // strip an inline style straight back off again.
  })

  app.registerCallback(Events.APPLICATION_READY, () => {
    // Before LiveView binds its clicks: a `data-confirm` click waits for an answer.
    installConfirm()
    app.liveSocket = initializeLiveSocket({ ...hooks, ...brandoHooks(app) })
    if (enableDebug) {
      app.liveSocket.enableDebug()
    }
    installUICommands(app)
    installFloatingDropdowns(app)
    installOpeningRows(app.liveSocket)
    installTooltips()
    installShortcuts(app)
    installAuthMotion()
  })

  // Optimistic (non-sticky) class toggle for select option rows. Dispatched
  // via JS.dispatch so the class is a plain mutation that morphdom reconciles
  // to server truth on the next patch — JS.toggle_class would putSticky the
  // class and fight the server render (e.g. deselect re-appearing as selected).
  window.addEventListener('b:option:toggle-selected', (e) => {
    e.target.classList.toggle('option-selected')
  })

  window.addEventListener('phx:b:component:remount', ({ detail }) => {
    app.components
      .filter(cmp => !detail?.skip_rich_text || cmp.el?.dataset.tiptapType !== 'rich_text')
      .forEach((cmp) => cmp.remount())
  })

  window.addEventListener('phx:b:component:remount_block', ({ detail }) => {
    const blockEl = document.querySelector(`[data-block-uid="${detail.uid}"]`)
    if (blockEl) {
      // `skip_focused`: another editor changed a block this editor works in.
      // The widget with the focus keeps what is being typed into it.
      const active = document.activeElement
      app.components
        .filter((cmp) => blockEl.contains(cmp.el))
        .filter((cmp) => !(detail.skip_focused && active && cmp.el.contains(active)))
        .forEach((cmp) => cmp.remount())
    }
  })

  window.addEventListener('phx:page-loading-start', () => {
    topbar.delayedShow(200)
  })

  window.addEventListener('phx:js-exec', ({ detail }) => {
    document.querySelectorAll(detail.to).forEach((el) => {
      liveSocket.execJS(el, el.getAttribute(detail.attr))
    })
  })

  window.addEventListener('phx:page-loading-stop', ({ detail }) => {
    topbar.hide()
    app.toast?.refreshWork()

    if (detail.kind === 'redirect') {
      if (app.reconnected) {
        app.reconnected = false
      }

      // remove current active
      const currentActiveItem = document.querySelector('#navigation .active')
      if (currentActiveItem) {
        currentActiveItem.classList.remove('active')
      }

      const newActiveItem = document.querySelector(
        `#navigation [data-phx-link][href="${window.location.pathname + window.location.search}"]`
      )
      if (newActiveItem) {
        newActiveItem.classList.add('active')
      }
    }

    if (detail.kind === 'initial' && !app.reconnected) {
      app.presence.setUrl(detail.to)
    }
  })

  const getHeights = () => {
    const progressItems = Dom.all('.progress-item')

    if (!progressItems.length) {
      return 0
    }

    let height = 0

    progressItems.forEach((item) => {
      height += item.clientHeight
    })

    return height
  }

  const $progressWrapper = Dom.find('.progress-wrapper')
  let $progress

  if ($progressWrapper) {
    $progress = Dom.find($progressWrapper, '.progress')
    set($progressWrapper, { transform: 'translateY(-100%)' })
  }

  if (app.userToken) {
    // The Chrome LiveView sends fresh tokens on every mount and every few
    // hours, so a long-open tab can still reconnect after a server restart
    window.addEventListener('phx:brando:socket_tokens', ({ detail }) => {
      app.userToken = detail.user_token
      const metaScope = Dom.find('meta[name="realtime_scope"]')
      if (metaScope) metaScope.setAttribute('content', detail.realtime_scope)
    })

    // A function, read on every connect attempt, so a reconnect uses the
    // newest token rather than the one the page was loaded with
    app.userSocket = new Socket('/admin/socket', {
      params: () => ({ token: app.userToken }),
    })
    app.userSocket.connect()

    app.userChannel = app.userSocket.channel(`user:${app.userId}`, {})
    // A function, so a rejoin after a server restart reports the page the
    // user is on now rather than the one the tab was first loaded at
    app.lobbyChannel = app.userSocket.channel('lobby', () => ({
      url: window.location.pathname,
      scope_token: document.querySelector('meta[name="realtime_scope"]')?.content,
    }))

    app.lobbyChannel.on('toast', (data) => {
      app.toast.mutation(data.level, data.payload)
    })

    app.userChannel.on('toast', (data) => {
      app.toast.notification(data.level, data.payload)
    })

    app.userChannel.on('work', (entry) => {
      app.toast.work(entry)
    })

    // Sent after each join: the work running now
    app.userChannel.on('work:sync', ({ work }) => {
      app.toast.syncWork(work)
    })

    app.userChannel.on('progress_popup', (data) => {
      app.toast.progressPopup(data.payload)
    })

    app.userChannel.on('progress:show', () => {
      animate($progressWrapper, { y: '0%' }, { ease: ease.circOut, duration: 0.35 })
    })

    app.userChannel.on('progress:hide', () => {
      animate($progressWrapper, { y: '-100%' }, { ease: ease.circIn, duration: 0.35 })
    })

    app.userChannel.on(
      'progress:update',
      ({ status, content: { key, filename, percent } }) => {
        const keyEl = Dom.find(`[data-progress-key="${key}"]`)

        if (keyEl) {
          const filenameEl = Dom.find(keyEl, '.filename')
          const descriptionEl = Dom.find(keyEl, '.description')
          const percentEl = Dom.find(keyEl, '.percent')

          filenameEl.innerHTML = filename
          descriptionEl.innerHTML = status
          percentEl.innerHTML = `${percent}%`

          if (parseInt(percent) === 100) {
            keyEl.remove()
            set($progressWrapper, { height: `${getHeights()}px` })
          }
        } else {
          const updateProgress = document.createRange()
            .createContextualFragment(`
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
          set(keyEl, { opacity: 1 })
        }

        set($progressWrapper, { height: `${getHeights()}px` })
      }
    )

    app.userChannel.join().receive('ok', (params) => {

      if (app.vsn) {
        // we've connected before. see if versions match!
        if (app.vsn !== params.vsn) {
          // new version, alert user
          alertError(
            '👀',
            'The application was updated while you were logged in. It is recommended to refresh the page, but make sure you have saved your work first.'
          )
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
  }

  return app
}
