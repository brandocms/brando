// Passkeys (WebAuthn). The server makes the options and checks the result;
// this hook only hands them to the browser's authenticator and back.
//
//   data-passkey="create" — register a passkey. On a form: its submit asks
//     the server (`data-options-event`, with the form's fields) for creation
//     options, and sends the new credential to `data-result-event`.
//   data-passkey="get" — confirm with a passkey: a click asks
//     `data-options-event` for request options and sends the assertion to
//     `data-result-event`.
//   data-passkey="login" — sign in, before there is a session: a click posts
//     to `data-options-url` (with `data-mode`), and the assertion is written
//     into the form `data-form` and submitted to the login controller, with
//     the remember-me checkbox `data-remember`, if any.
//
// When the browser has no passkeys or the user cancels, `data-error-event`
// gets `{error}` (LiveView modes), or `[data-passkey-error]` in the form is
// shown (login).

const toBase64Url = (buffer) =>
  btoa(String.fromCharCode(...new Uint8Array(buffer)))
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '')

const fromBase64Url = (text) => {
  const base64 = text.replace(/-/g, '+').replace(/_/g, '/')
  const padded = base64 + '='.repeat((4 - (base64.length % 4)) % 4)
  return Uint8Array.from(atob(padded), (char) => char.charCodeAt(0))
}

const creationOptions = (options) => ({
  ...options,
  challenge: fromBase64Url(options.challenge),
  user: { ...options.user, id: fromBase64Url(options.user.id) },
  excludeCredentials: (options.excludeCredentials || []).map((credential) => ({
    ...credential,
    id: fromBase64Url(credential.id),
  })),
})

const requestOptions = (options) => ({
  ...options,
  challenge: fromBase64Url(options.challenge),
  allowCredentials: (options.allowCredentials || []).map((credential) => ({
    ...credential,
    id: fromBase64Url(credential.id),
  })),
})

const credentialPayload = (credential) => ({
  id: toBase64Url(credential.rawId),
  attestation_object: toBase64Url(credential.response.attestationObject),
  client_data_json: toBase64Url(credential.response.clientDataJSON),
  transports: credential.response.getTransports ? credential.response.getTransports() : [],
})

const assertionPayload = (credential) => ({
  id: toBase64Url(credential.rawId),
  authenticator_data: toBase64Url(credential.response.authenticatorData),
  signature: toBase64Url(credential.response.signature),
  client_data_json: toBase64Url(credential.response.clientDataJSON),
  user_handle: credential.response.userHandle ? toBase64Url(credential.response.userHandle) : '',
})

const supported = () => typeof window.PublicKeyCredential !== 'undefined' && !!navigator.credentials

export default () => ({
  mounted() {
    this.mode = this.el.dataset.passkey
    this.handler = (event) => {
      event.preventDefault()
      if (this.busy) return
      this.busy = true
      this.run().finally(() => {
        this.busy = false
      })
    }
    this.el.addEventListener(this.mode === 'create' ? 'submit' : 'click', this.handler)
  },

  destroyed() {
    this.el.removeEventListener(this.mode === 'create' ? 'submit' : 'click', this.handler)
  },

  push(event, payload) {
    return new Promise((resolve) => this.pushEventTo(this.el, event, payload, (reply) => resolve(reply)))
  },

  fail(error) {
    const name = (error && error.name) || 'Error'
    if (this.mode === 'login') {
      const form = document.querySelector(this.el.dataset.form)
      const message = form && form.querySelector('[data-passkey-error]')
      if (message) message.hidden = false
    } else if (this.el.dataset.errorEvent) {
      this.pushEventTo(this.el, this.el.dataset.errorEvent, { error: name })
    }
  },

  async run() {
    try {
      if (!supported()) throw Object.assign(new Error('unsupported'), { name: 'NotSupportedError' })
      if (this.mode === 'create') return await this.create()
      if (this.mode === 'get') return await this.get()
      if (this.mode === 'login') return await this.login()
    } catch (error) {
      this.fail(error)
    }
  },

  async create() {
    // The form's fields (a name, and the password or a code that proves it is
    // the user) go with the request for options; only the name goes back with
    // the new credential.
    const fields = Object.fromEntries(new FormData(this.el))
    const reply = await this.push(this.el.dataset.optionsEvent, fields)
    if (!reply || !reply.publicKey) return
    const credential = await navigator.credentials.create({ publicKey: creationOptions(reply.publicKey) })
    await this.push(this.el.dataset.resultEvent, { name: fields.name, ...credentialPayload(credential) })
  },

  async get() {
    const reply = await this.push(this.el.dataset.optionsEvent, {})
    if (!reply || !reply.publicKey) return
    const credential = await navigator.credentials.get({ publicKey: requestOptions(reply.publicKey) })
    await this.push(this.el.dataset.resultEvent, assertionPayload(credential))
  },

  async login() {
    const csrf = document.querySelector("meta[name='csrf-token']").getAttribute('content')
    const response = await fetch(this.el.dataset.optionsUrl, {
      method: 'POST',
      credentials: 'same-origin',
      headers: { 'content-type': 'application/json', 'x-csrf-token': csrf },
      body: JSON.stringify({ mode: this.el.dataset.mode }),
    })
    if (!response.ok) throw new Error('options')
    const { publicKey } = await response.json()
    const credential = await navigator.credentials.get({ publicKey: requestOptions(publicKey) })
    const form = document.querySelector(this.el.dataset.form)
    for (const [name, value] of Object.entries(assertionPayload(credential))) {
      form.querySelector(`[name="passkey[${name}]"]`).value = value
    }
    const remember = this.el.dataset.remember && document.querySelector(this.el.dataset.remember)
    if (remember) form.querySelector('[name="remember_me"]').value = remember.checked ? 'true' : 'false'
    form.submit()
  },
})
