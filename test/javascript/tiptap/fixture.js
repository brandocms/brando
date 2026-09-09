import { tick } from 'svelte'
import hookFactory from '../../../assets/src/hooks/TipTap/index.js'
import '../../../assets/css/components/Form/Input/TipTap.css'

const app = { components: [] }
let sequence = 0
const errors = []
window.addEventListener('error', event => errors.push(event.message))
window.harness = {
  app, errors,
  async create(options = {}) {
    const id = `editor-${++sequence}`
    const form = document.createElement('form')
    form.innerHTML = `<div class="field-wrapper"><label class="control-label">Introduction</label><div class="tiptap-wrapper"><div id="${id}" data-tiptap-type="rich_text"><div class="tiptap-target"></div><input type="hidden" class="tiptap-text" id="${id}-text" name="page[body]"></div></div></div><button type="button">After editor</button>`
    document.getElementById('fixture').append(form)
    const el = form.querySelector(`#${id}`)
    if (options.formTarget) form.setAttribute('phx-target', options.formTarget)
    if (options.editorTarget) el.setAttribute('phx-target', options.editorTarget)
    if (options.nestedComponent) form.querySelector('.field-wrapper').dataset.phxComponent = options.nestedComponent
    el.dataset.tiptapExtensions = options.extensions ?? 'all'
    el.dataset.tiptapStyles = JSON.stringify(options.styles || [])
    el.dataset.footnotes = String(options.footnotes ?? true)
    el.dataset.tiptapAi = String(options.ai ?? true)
    el.dataset.tiptapField = 'body'
    el.querySelector('input').value = options.content || '<p>Havglimt is a small retreat by the sea.</p>'
    const handlers = new Map(), sent = [], commitReplies = []
    const hook = Object.assign(hookFactory(app), {
      el,
      handleEvent(name, handler) { handlers.set(name, handler); return name },
      removeHandleEvent(name) { handlers.delete(name) },
      pushEventTo(destination, name, payload, callback) {
        const target = typeof destination === 'string' ? destination : destination.closest('[data-phx-component]')?.dataset.phxComponent || null
        sent.push({ name, payload, target })
        if (options.deferCommits && name === 'commit_tiptap') commitReplies.push(callback)
        else callback?.({})
      },
    })
    hook.mounted()
    await tick()
    this.current = { hook, sent, handlers, form, commitReplies, get editor() { return hook._editor }, input: el.querySelector('.tiptap-text'), emit(name, data) { handlers.get(`b:tiptap:${name}:${id}`)?.(data) } }
    return id
  },
}
const style = document.createElement('style')
style.textContent = 'body{font:14px/1.5 system-ui;margin:24px;background:#f4f7f5;color:#272b2a}#fixture{max-width:850px;margin:auto}.tiptap-wrapper{border:1px solid #dce2dc;background:white}.control-label{display:block;margin-bottom:8px}.ProseMirror{box-sizing:border-box}.ProseMirror p{font-size:16px}.ProseMirror ul{list-style:disc}.ProseMirror ol{list-style:decimal}button{font:inherit;cursor:pointer}input{font:inherit}'
document.head.append(style)
