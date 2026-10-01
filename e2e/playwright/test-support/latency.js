// Holds back LiveView frames from the server, in order, so a test can see what
// the page shows before the server has answered. Locally every round trip is a
// few milliseconds, which hides whether an interaction waits for one.
//
//   const latency = await serverLatency(page) // before page.goto
//   latency.set(1500)
//
// Must be installed before the page opens its socket. Frames to the server are
// forwarded untouched.
export async function serverLatency(page) {
  let delay = 0
  let last = 0

  await page.routeWebSocket('**/live/websocket*', (socket) => {
    const server = socket.connectToServer()

    server.onMessage((message) => {
      // Never earlier than the frame before it: lowering the delay must not
      // reorder frames already held.
      const at = Math.max(Date.now() + delay, last)
      last = at
      setTimeout(() => {
        if (!page.isClosed()) socket.send(message)
      }, at - Date.now())
    })
  })

  return {
    set(ms) {
      delay = ms
    },
  }
}
