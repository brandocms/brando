import TipTap from '../../components/TipTap/TipTap.svelte'
import { mount, unmount } from 'svelte'
import { createDocument } from '@tiptap/core'
import { EditorState, Selection } from '@tiptap/pm/state'
import { readFootnoteLabels, renumberFootnotes } from '../../components/TipTap/extensions/Footnote'
import { captureRange, mapRange } from '../../components/TipTap/selection'
import { linkClass } from '../../components/TipTap/extensions/Link'
import { normalizeUrl } from '../../components/TipTap/urlPolicy'
import { resolveCapabilities } from '../../components/TipTap/config'

const readJSON = (value, fallback = {}) => { try { return value ? JSON.parse(value) : fallback } catch { return fallback } }

export default app => ({
  mounted() {
    this._handlers = []
    this._revision = -1
    this._destroyed = false
    this.mount()
    this.setupHandlers()
    app.components.push(this)
  },

  mount() {
    this._configuration = this.configuration()
    this._input = this.el.querySelector('.tiptap-text')
    this._field = this.el.dataset.tiptapType === 'rich_text' ? this._input.name : this.el.closest('.blocks-wrapper')?.dataset.blockField
    const onToggle = markType => (_href, _target, _identifier) => {
      const editor = this._editor
      if (!editor?.isEditable) return
      if (editor.isActive('link') && editor.state.selection.empty) editor.commands.extendMarkRange('link')
      this._linkRange = captureRange(editor)
      this._linkRequest = crypto.randomUUID()
      const attrs = editor.getAttributes('link')
      const scope = this.el.closest('.blocks-wrapper') || this._input.form || this.el
      const anchors = [...scope.querySelectorAll('[data-type="jump-anchor"][id], [data-block-anchor]')].map(el => el.id || el.dataset.blockAnchor).filter(Boolean)
      this.pushEventTo(this.el, 'tiptap_link_dialog', {
        current_href: attrs.href || '', current_target: attrs.target ?? null, current_rel: attrs.rel || '', current_class: attrs.class || '',
        current_identifier_id: attrs['data-identifier-id'] || null, mark_type: markType, tiptap_id: this.el.id, request_id: this._linkRequest,
        link_text: editor.state.doc.textBetween(this._linkRange.from, this._linkRange.to), has_selection: !editor.state.selection.empty, anchors,
        appearances: ['link', 'button'].filter(type => resolveCapabilities(this.el.dataset.tiptapExtensions).includes(type) || (type === 'button' ? String(attrs.class || '').split(/\s+/).includes('action-button') : editor.isActive('link'))),
      })
    }
    this._instance = mount(TipTap, {
      target: this.el.querySelector('.tiptap-target'),
      props: {
        content: this._input.value || '', extensions: this.el.getAttribute('data-tiptap-extensions'), styles: this.el.dataset.tiptapStyles,
        labels: readJSON(this.el.dataset.tiptapLabels), labelMode: this.el.dataset.tiptapLabelMode || 'compact', typography: readJSON(this.el.dataset.tiptapTypography),
        accessibility: this.accessibility(),
        onFocus: () => this.pushEventTo(this.el, 'focus', { field: this._field }),
        onBlur: () => { if (this.el.dataset.footnotes === 'true' || this.el.closest('.block-slot-drawer')) this.commitInput() },
        onToggleLink: onToggle('link'), onToggleButton: onToggle('button'),
        footnotes: this.el.dataset.footnotes === 'true', footnoteLabels: readFootnoteLabels(this.el),
        onOpenFootnote: (uid, number) => {
          if (!uid) this._footnoteRange = captureRange(this._editor, { from: this._editor.state.selection.to, to: this._editor.state.selection.to })
          this.pushEventTo(this.el, uid ? 'open_footnote' : 'create_footnote', { uid, number, ref_name: this.el.dataset.footnoteRef, field: this.el.dataset.footnoteField, tiptap_id: this.el.id })
        },
        aiEnabled: this.el.dataset.tiptapAi === 'true',
        onGenerateAi: payload => this.pushEventTo(this.el, 'tiptap_ai_generate', { ...payload, tiptap_id: this.el.id, ref_name: this.el.dataset.footnoteRef, field_name: this._input.name, field_key: this.el.dataset.tiptapField }),
        onCancelAi: request_id => this.pushEventTo(this.el, 'tiptap_ai_cancel', { request_id, tiptap_id: this.el.id }),
        onEditorCreated: editor => {
          this._editor = editor
          if (this._restoreSelection) { editor.commands.setTextSelection(this._restoreSelection); this._restoreSelection = null }
          editor.on('transaction', ({ transaction }) => {
            this._linkRange = mapRange(this._linkRange, transaction)
            this._footnoteRange = mapRange(this._footnoteRange, transaction)
          })
          this.updateEditable()
          queueMicrotask(() => { if (!this._destroyed) renumberFootnotes(this.el) })
        },
        tiptapInput: this._input,
      },
    })
  },

  accessibility() {
    const label = this.el.dataset.tiptapLabel || this.el.closest('.field-wrapper')?.querySelector('.control-label')?.textContent?.trim() || 'Text'
    return { 'aria-label': label, 'aria-describedby': this.el.dataset.tiptapDescribedby || '', 'aria-invalid': this.el.dataset.tiptapInvalid || 'false', 'aria-required': this.el.dataset.tiptapRequired || 'false' }
  },

  updateEditable() {
    const locked = !!this.el.closest('.block-locked, [data-presence-locked="true"], .field-locked') || this.el.dataset.tiptapReadonly === 'true'
    if (this._editor && !this._editor.isDestroyed && this._editor.isEditable === locked) {
      this._editor.setEditable(!locked, false)
      this._editor.view.dispatch(this._editor.state.tr.setMeta('brando:editable', !locked))
    }
  },

  updated() {
    if (this.configuration() !== this._configuration) {
      // A schema/configuration change is deliberate (e.g. module preview).
      // Preserve the document, but do not replay history under different rules.
      const content = this._editor.getHTML(), selection = this._editor.state.selection
      unmount(this._instance)
      this._editor = null
      this._input.value = content
      this._restoreSelection = { from: selection.from, to: selection.to }
      this.mount()
      this._linkRange = null; this._footnoteRange = null
    }
    this._editor?.setOptions({ editorProps: { ...this._editor.options.editorProps, attributes: { ...this._editor.options.editorProps.attributes, ...this.accessibility() } } })
    this.updateEditable()
    this.observeEditable?.()
    renumberFootnotes(this.el)
  },

  configuration() { return ['tiptapExtensions', 'tiptapStyles', 'tiptapTypography', 'footnotes', 'tiptapAi'].map(key => this.el.dataset[key] || '').join('\u001f') },

  setupHandlers() {
    this._handlers.push(this.handleEvent(`b:tiptap:set_link:${this.el.id}`, payload => {
      if (payload.request_id && payload.request_id !== this._linkRequest) return
      if (payload.cancel || payload.closed) { this._instance.linkClosed?.(); this._linkRange = null; return }
      const editor = this._editor, range = this._linkRange
      const result = applied => this.pushEventTo(this.el, 'tiptap_link_result', { request_id: this._linkRequest, applied })
      if (!editor?.isEditable || !range?.valid) { result(false); return }
      const chain = editor.chain().setTextSelection({ from: range.from, to: range.to })
      if (payload.unset) result(chain.unsetLink().run())
      else {
        const href = normalizeUrl(payload.href)
        if (!href) { result(false); return }
        const attrs = { href, target: payload.target ?? null, rel: payload.rel ?? null, class: linkClass(payload.class, payload.mark_type === 'button'), 'data-identifier-id': payload.identifier_id ? String(payload.identifier_id) : null }
        // Preserve marks and wording unless the author explicitly changes text.
        const previousText = editor.state.doc.textBetween(range.from, range.to)
        const text = payload.link_text || previousText || href
        const applied = range.from === range.to || text !== previousText
          ? chain.insertContent({ type: 'text', text, marks: [{ type: 'link', attrs }] }).run()
          : chain.setLink(attrs).run()
        result(applied)
      }
      this._linkRange = null
    }))
    this._handlers.push(this.handleEvent(`b:tiptap:insert_footnote:${this.el.id}`, ({ uid, restore }) => {
      if (!this._editor?.isEditable) return
      const range = this._footnoteRange || (restore ? captureRange(this._editor, { from: this._editor.state.selection.to, to: this._editor.state.selection.to }) : null)
      if (!range?.valid) { this._instance.showError?.(); return }
      this._footnoteRange = null
      const chain = this._editor.chain()
      if (restore) chain.focus()
      chain.insertContentAt(range.to, { type: 'footnote', attrs: { uid } }, { updateSelection: false }).run()
      renumberFootnotes(this.el)
      this.commitInput(() => document.getElementById(`block-slot-drawer-${uid}`)?.querySelector('[contenteditable="true"]')?.focus())
    }))
    this._handlers.push(this.handleEvent(`b:tiptap:ai:${this.el.id}`, payload => this._instance.receiveAi?.(payload)))
    this._handlers.push(this.handleEvent('b:tiptap:update', payload => { if (payload.id === this.el.id) this.replaceContent(payload) }))
    this._clearListener = () => { if (this._editor?.isEditable) this._editor.commands.clearContent(true) }
    this._aiListener = () => this._instance.openAi?.()
    this._compositionEnd = () => { if (this._pendingReplacement) { const payload = this._pendingReplacement; this._pendingReplacement = null; this.replaceContent(payload) } }
    this.el.addEventListener('brando:tiptap:clear', this._clearListener)
    this.el.addEventListener('brando:tiptap:ai', this._aiListener)
    this.el.addEventListener('compositionend', this._compositionEnd)
    this._lockObserver = new MutationObserver(() => this.updateEditable())
    this.observeEditable()
  },

  observeEditable() {
    if (!this._lockObserver) return
    this._lockObserver.disconnect()
    // Locks live on ancestors. Do not subscribe every editor to every sibling
    // editor's selection classes and other subtree decorations.
    let ancestor = this.el
    while (ancestor && ancestor !== document.body) {
      this._lockObserver.observe(ancestor, { attributes: true, attributeFilter: ['class', 'data-presence-locked', 'data-tiptap-readonly'] })
      ancestor = ancestor.parentElement
    }
  },

  replaceContent({ html, revision, epoch } = {}) {
    if (epoch != null && epoch !== this._epoch) { this._epoch = epoch; this._revision = -1 }
    if (!this._editor || this._destroyed || revision != null && revision <= this._revision) return
    if (this._editor.view.composing) {
      if (revision == null || this._pendingReplacement?.revision == null || epoch !== this._pendingReplacement.epoch || revision > this._pendingReplacement.revision) this._pendingReplacement = { html, revision, epoch }
      return
    }
    if (revision != null) this._revision = revision
    const doc = createDocument(html ?? this._input.value ?? '', this._editor.schema, this._editor.options.parseOptions)
    if (doc.eq(this._editor.state.doc)) return
    this._linkRange = null; this._footnoteRange = null
    const state = EditorState.create({ schema: this._editor.schema, doc, plugins: this._editor.state.plugins, selection: Selection.near(doc.resolve(Math.min(this._editor.state.selection.from, doc.content.size))) })
    this._editor.view.updateState(state)
    this._editor.emit('transaction', { editor: this._editor, transaction: state.tr.setMeta('brando:replacement', true) })
    this._input.value = this._editor.getHTML()
    renumberFootnotes(this.el)
  },

  // Compatibility for the application's existing scoped replacement events.
  // Equivalent echoes and unrelated updates never destroy the Editor/history.
  remount() { this.replaceContent() },

  commitInput(onCommitted = () => {}) {
    const input = this._input, form = input?.form
    if (!form || !this._editor || this._destroyed) return
    input.value = this._editor.getHTML()
    const fields = Array.from(new FormData(form)).filter(([, value]) => typeof value === 'string')
    this.pushEventTo(this.el, 'commit_tiptap', { form: new URLSearchParams(fields).toString(), target: input.name.match(/[^\[\]]+/g) }, onCommitted)
  },

  destroyed() {
    this._destroyed = true
    this._lockObserver?.disconnect()
    this.el.removeEventListener('brando:tiptap:clear', this._clearListener)
    this.el.removeEventListener('brando:tiptap:ai', this._aiListener)
    this.el.removeEventListener('compositionend', this._compositionEnd)
    this._handlers.forEach(ref => this.removeHandleEvent?.(ref))
    const index = app.components.indexOf(this)
    if (index >= 0) app.components.splice(index, 1)
    unmount(this._instance)
  },
})
