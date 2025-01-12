import { LiveSocket } from 'phoenix_live_view'
import { Socket } from 'phoenix'
import Uploaders from './uploaders'

export default (hooks) => {
  let csrfToken = document
    .querySelector("meta[name='csrf-token']")
    ?.getAttribute('content')
  let liveSocket = new LiveSocket('/live', Socket, {
    hooks: hooks,
    params: { _csrf_token: csrfToken },
    timeout: 70000,
    uploaders: Uploaders,
    metadata: {
      keydown: (e, el) => {
        return {
          key: e.key,
          metaKey: e.metaKey,
          shiftKey: e.shiftKey,
          repeat: e.repeat,
        }
      },
    },
  })

  // connect if there are any LiveViews on the page
  liveSocket.connect()

  // expose liveSocket on window for web console debug logs and latency simulation:
  window.liveSocket = liveSocket
  return liveSocket
}
