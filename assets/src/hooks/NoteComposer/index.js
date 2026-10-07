// The text box of a note or a reply (NotesDrawer). Typing `@` and the start
// of a name lists the people who can be mentioned (the panel's
// `data-mention-users`); choosing one writes `@Name` and records the id in
// the form's hidden `data-mentions` input, which the server turns into a
// mention token. Enter sends, Shift+Enter starts a new line.
const MAX = 6

export default () => ({
  mounted() {
    this.form = this.el.form
    this.hidden = this.form?.querySelector('[data-mentions]')
    this.picker = this.el.parentElement.querySelector('.note-mention-picker')
    this.panel = this.el.closest('[data-notes-panel]')
    this.mentions = new Map()
    this.items = []
    this.active = 0

    this.onInput = () => {
      this.fit()
      this.prune()
      this.suggest()
    }
    this.onKeydown = event => this.keydown(event)
    this.onBlur = () => setTimeout(() => this.closePicker(), 150)
    this.el.addEventListener('input', this.onInput)
    this.el.addEventListener('keydown', this.onKeydown)
    this.el.addEventListener('blur', this.onBlur)
  },

  // Grow with the text. Measured on input only: the panel may be closed
  // (zero wide) when the box mounts.
  fit() {
    this.el.style.height = 'auto'
    if (this.el.value) this.el.style.height = `${this.el.scrollHeight}px`
    else this.el.style.removeProperty('height')
  },

  users() {
    try {
      return JSON.parse(this.panel?.dataset.mentionUsers || '[]')
    } catch {
      return []
    }
  },

  // The `@word` being typed at the caret.
  query() {
    const caret = this.el.selectionStart
    const match = this.el.value.slice(0, caret).match(/(?:^|\s)@([^\s@]{0,40})$/u)
    return match ? { text: match[1].toLowerCase(), start: caret - match[1].length - 1, end: caret } : null
  },

  suggest() {
    const query = this.query()
    if (!query || !this.picker) return this.closePicker()

    this.items = this.users()
      .filter(user => user.name && user.name.toLowerCase().split(/\s+/).some(word => word.startsWith(query.text)))
      .slice(0, MAX)
    this.active = 0
    this.render()
  },

  render() {
    const picker = this.picker
    picker.replaceChildren()
    picker.id ||= `${this.el.id}-picker`
    picker.setAttribute('role', 'listbox')

    if (!this.items.length) {
      const empty = document.createElement('p')
      empty.className = 'note-mention-empty'
      empty.textContent = this.panel?.dataset.mentionEmpty || ''
      picker.append(empty)
    }

    this.items.forEach((user, index) => {
      const option = document.createElement('button')
      option.type = 'button'
      option.id = `${picker.id}-${user.id}`
      option.setAttribute('role', 'option')
      option.setAttribute('aria-selected', String(index === this.active))
      option.textContent = user.name
      option.addEventListener('pointerdown', event => event.preventDefault())
      option.addEventListener('click', () => this.choose(user))
      picker.append(option)
    })

    picker.hidden = false
    this.el.setAttribute('aria-expanded', 'true')
    this.el.setAttribute('aria-controls', picker.id)
    const active = this.items[this.active]
    if (active) this.el.setAttribute('aria-activedescendant', `${picker.id}-${active.id}`)
    else this.el.removeAttribute('aria-activedescendant')
  },

  closePicker() {
    if (!this.picker || this.picker.hidden) return
    this.picker.hidden = true
    this.items = []
    this.el.setAttribute('aria-expanded', 'false')
    this.el.removeAttribute('aria-activedescendant')
  },

  choose(user) {
    const query = this.query()
    if (!query) return this.closePicker()
    const value = this.el.value
    const insert = `@${user.name} `
    this.el.value = value.slice(0, query.start) + insert + value.slice(query.end)
    const caret = query.start + insert.length
    this.el.setSelectionRange(caret, caret)
    this.mentions.set(String(user.id), user.name)
    this.sync()
    this.closePicker()
    this.fit()
    this.el.focus()
  },

  // Drop mentions whose `@Name` was edited away.
  prune() {
    let changed = false
    this.mentions.forEach((name, id) => {
      if (!this.el.value.includes(`@${name}`)) {
        this.mentions.delete(id)
        changed = true
      }
    })
    if (changed) this.sync()
  },

  sync() {
    if (this.hidden) this.hidden.value = [...this.mentions.keys()].join(',')
  },

  keydown(event) {
    const open = this.picker && !this.picker.hidden

    if (open && this.items.length && ['ArrowDown', 'ArrowUp'].includes(event.key)) {
      event.preventDefault()
      this.active = (this.active + (event.key === 'ArrowDown' ? 1 : -1) + this.items.length) % this.items.length
      this.render()
      return
    }

    if (open && this.items.length && (event.key === 'Enter' || event.key === 'Tab')) {
      event.preventDefault()
      this.choose(this.items[this.active])
      return
    }

    if (open && event.key === 'Escape') {
      event.preventDefault()
      event.stopPropagation()
      this.closePicker()
      return
    }

    if (event.key === 'Enter' && !event.shiftKey && !event.isComposing && this.el.hasAttribute('data-submit-on-enter')) {
      event.preventDefault()
      if (this.el.value.trim()) this.form?.requestSubmit()
    }
  },
})
