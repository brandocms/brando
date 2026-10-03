// The frontend editor's side of frontend edit mode. The editor runs in an
// iframe on the published page (`priv/static/js/frontend_edit.js`); this hook
// passes the server's preview HTML and editor state up to the page, and the
// page's requests (select another block, save) down to the server.
//
// Same origin only, both ways: the admin and the site share an origin.
const SOURCE = 'brando:frontend-edit'

export default () => ({
  mounted() {
    this.target = this.el.dataset.target
    // On `<html>`, which LiveView never patches: lets the sidebar hide admin
    // chrome that lives outside the view, like the progress popup.
    document.documentElement.classList.add('is-frontend-editor')

    this.onMessage = event => {
      if (
        event.origin !== window.location.origin ||
        event.source !== window.parent ||
        !event.data ||
        event.data.source !== SOURCE
      ) {
        return
      }

      if (event.data.type === 'select') {
        this.pushEvent('select', event.data.field ? { field: event.data.field } : { uid: event.data.uid })
      } else if (event.data.type === 'save') {
        // The form's own save button, so saving runs exactly as from here.
        document.getElementById(this.el.dataset.submitId)?.click()
      }
    }

    this.onClick = event => {
      if (event.target.closest('[data-frontend-edit-close]')) {
        this.post({ type: 'close' })
      }
    }

    window.addEventListener('message', this.onMessage)
    this.el.addEventListener('click', this.onClick)
    this.handleEvent('b:frontend-edit', payload => this.post(payload))
    this.post({ type: 'ready', target: this.target })
  },

  updated() {
    if (this.el.dataset.target !== this.target) {
      this.target = this.el.dataset.target
      this.post({ type: 'selected', target: this.target })
    }
  },

  destroyed() {
    window.removeEventListener('message', this.onMessage)
  },

  post(payload) {
    if (window.parent !== window) {
      window.parent.postMessage({ source: SOURCE, ...payload }, window.location.origin)
    }
  }
})
