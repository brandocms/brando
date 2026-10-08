/**
 * Brando.ShortcutSheet — the keyboard shortcut sheet, a native modal <dialog>
 * (`BrandoAdmin.Components.ShortcutSheet`).
 *
 * `?` opens it (see `shortcuts/`), and so do "Keyboard shortcuts" in the
 * command palette and in the user menu, by sending `brando:shortcuts:open`
 * to the dialog. Its rows are drawn from the registry each time it opens,
 * with the server's translated labels, so the sheet lists what the keys do
 * and the "go to" rows this user can follow. Escape or the close button
 * close it, and the focus goes back to where it was.
 *
 * The switch at its foot turns single-key shortcuts off and on in this
 * browser; ⌘K and ⌘S are not affected.
 */
import { GROUPS, SHORTCUTS, displayKeys, isMacPlatform } from '../../shortcuts/registry'
import { available, bindShortcut, characterKeysEnabled, setCharacterKeysEnabled } from '../../shortcuts'

function element(tag, attrs = {}, children = []) {
  const el = document.createElement(tag)
  Object.entries(attrs).forEach(([name, value]) => {
    if (name === 'text') el.textContent = value
    else el.setAttribute(name, value)
  })
  el.append(...children)
  return el
}

// How a screen reader says a key: "⌘" alone is read as a symbol, or not at all.
const SPOKEN = {
  '⌘': 'key_command',
  '⇧': 'key_shift',
  '⌥': 'key_option',
  '⌃': 'key_control',
  Ctrl: 'key_ctrl',
  Shift: 'key_shift',
  Alt: 'key_alt',
  '↑': 'key_up',
  '↓': 'key_down',
  '↵': 'key_enter',
  Esc: 'key_escape',
}

export default () => ({
  mounted() {
    this.dialog = this.el
    this.body = this.el.querySelector('[data-shortcut-sheet-body]')
    this.toggle = this.el.querySelector('[data-shortcut-sheet-character-keys]')
    this.labels = JSON.parse(this.el.dataset.labels || '{}')

    this.unbind = bindShortcut('help', () => this.open())

    this.onOpen = e => this.open(e.detail?.opener)
    this.el.addEventListener('brando:shortcuts:open', this.onOpen)

    this.el.addEventListener('click', e => {
      // A click on the backdrop lands on the dialog itself
      if (e.target === this.dialog || e.target.closest('[data-shortcut-sheet-close]')) this.dialog.close()
    })

    this.toggle?.addEventListener('change', () => setCharacterKeysEnabled(this.toggle.checked))

    this.dialog.addEventListener('close', () => {
      const opener = this.opener
      this.opener = null
      this.restoreFocus(opener)
    })
  },

  destroyed() {
    this.unbind?.()
    this.el.removeEventListener('brando:shortcuts:open', this.onOpen)
  },

  open(opener) {
    if (this.dialog.open) return true
    this.opener = opener || document.activeElement
    this.render()
    if (this.toggle) this.toggle.checked = characterKeysEnabled()
    this.dialog.showModal()
    // The title, not the close button: a screen reader reads the dialog's
    // name, and Tab goes on to the close button.
    this.el.querySelector('#shortcut-sheet-title')?.focus()
    return true
  },

  // The user menu hides its items as it closes: back to the menu itself then.
  restoreFocus(opener) {
    if (!opener || !opener.isConnected || typeof opener.focus !== 'function') return
    const visible = opener.checkVisibility ? opener.checkVisibility({ visibilityProperty: true }) : opener.getClientRects().length > 0
    const target = visible ? opener : opener.parentElement?.closest('[tabindex], button, a[href]')
    target?.focus({ preventScroll: true })
  },

  label(key) {
    return this.labels[key] || key
  },

  render() {
    const mac = isMacPlatform(navigator.userAgentData?.platform || navigator.platform || navigator.userAgent)
    const sections = GROUPS.map(group => {
      const rows = SHORTCUTS.filter(shortcut => shortcut.group === group && available(shortcut)).map(shortcut =>
        this.row(shortcut, mac)
      )
      const headingId = `shortcut-sheet-group-${group}`
      return element('section', { class: 'shortcut-sheet-group', 'aria-labelledby': headingId }, [
        element('h3', { id: headingId, class: 'shortcut-sheet-heading', text: this.label(`group_${group}`) }),
        element('dl', {}, rows),
      ])
    })
    this.body.replaceChildren(...sections)
  },

  row(shortcut, mac) {
    const alternatives = displayKeys(shortcut, mac)
    const joiner = shortcut.sequence ? this.label('then') : null
    const visible = []
    const spoken = []

    alternatives.forEach((keys, i) => {
      if (i > 0) {
        visible.push(element('span', { class: 'shortcut-sheet-or', text: '/' }))
        spoken.push(this.label('or'))
      }
      keys.forEach((key, j) => {
        if (j > 0 && joiner) visible.push(element('span', { class: 'shortcut-sheet-then', text: joiner }))
        visible.push(element('kbd', { text: key }))
      })
      spoken.push(keys.map(key => (SPOKEN[key] ? this.label(SPOKEN[key]) : key)).join(joiner ? ` ${joiner} ` : ' '))
    })

    return element('div', { class: 'shortcut-sheet-row', 'data-shortcut': shortcut.id }, [
      element('dt', { text: this.label(shortcut.id) }),
      element('dd', {}, [
        element('span', { class: 'shortcut-sheet-keys', 'aria-hidden': 'true' }, visible),
        element('span', { class: 'shortcut-sheet-sr', text: spoken.join(' ') }),
      ]),
    ])
  },
})
