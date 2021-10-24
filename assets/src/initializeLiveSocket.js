import { LiveSocket } from './phoenix_live_view'
import { Socket } from 'phoenix'
import morphdomCallbacks from './morphdomCallbacks'

export default hooks => {
  let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
  let liveSocket = new LiveSocket("/live", Socket, {
    hooks: hooks,
    params: { _csrf_token: csrfToken },
    timeout: 70000,
    dom: morphdomCallbacks
  })

  // connect if there are any LiveViews on the page
  liveSocket.connect()

  // expose liveSocket on window for web console debug logs and latency simulation:
  liveSocket.enableDebug()
  // >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
  // >> liveSocket.disableLatencySim()
  window.liveSocket = liveSocket
}