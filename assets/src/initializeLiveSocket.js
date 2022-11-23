import { LiveSocket } from 'phoenix_live_view'
import { Socket } from 'phoenix'

export default (hooks, enableDebug) => {
  let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute('content')
  let liveSocket = new LiveSocket('/live', Socket, {
    hooks: hooks,
    params: { _csrf_token: csrfToken },
    timeout: 70000
  })

  // connect if there are any LiveViews on the page
  liveSocket.connect()

  if (enableDebug) {
    liveSocket.enableDebug()
  }

  // expose liveSocket on window for web console debug logs and latency simulation:
  window.liveSocket = liveSocket

  return liveSocket
}
