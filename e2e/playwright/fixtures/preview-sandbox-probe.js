// An inert probe for tests/blocks/live-preview-sandbox.spec.js. The test adds
// it to a live preview page, where an editor's script would run, and it
// records on the page's <html> what it could reach: the admin page framing
// it, the window that opened it, and the admin pages with the viewer's
// session. It reads only a document's title and changes nothing outside the
// preview.
;(async () => {
  const reach = read => {
    try {
      read()
      return 'reachable'
    } catch (error) {
      return error.name
    }
  }

  const result = {
    origin: self.origin,
    parentDocument: window.parent === window ? 'none' : reach(() => window.parent.document.title),
    topDocument: window.top === window ? 'none' : reach(() => window.top.document.title),
    opener: window.opener === null ? 'none' : reach(() => window.opener.document.title),
  }

  // Readable only with the viewer's cookies and a CORS grant
  try {
    const response = await fetch('/admin', { credentials: 'include' })
    result.adminFetch = 'status ' + response.status
  } catch (error) {
    result.adminFetch = error.name
  }

  // Sent without reading the response: the test checks which cookies it carries
  try {
    await fetch('/admin?preview-sandbox-probe', { mode: 'no-cors', credentials: 'include' })
  } catch (_) {}

  document.documentElement.dataset.sandboxProbe = JSON.stringify(result)
})()
