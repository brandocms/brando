/**
 * Brando frontend edit mode
 *
 * Added to frontend pages by `Brando.Plug.FrontendEdit` for signed-in admins.
 * With edit mode off it shows an "Edit page" button. With it on, it outlines
 * blocks under the pointer, opens the clicked block in a sidebar (an admin
 * view in an iframe) and patches the page as the block is edited there.
 *
 * Reads its configuration from `#brando-frontend-edit-config`. Block patching
 * comes from `block_patch.js` (`window.BrandoBlockPatch`).
 *
 * Besides blocks, entry fields a template marks with `editable_field` or
 * `editable` can be clicked (`[+:E<key>]` and `[+:W<key>]` comments). Field
 * targets are their keys (`Schema:id:field`), block targets their uids; a uid
 * never contains a colon.
 *
 * The sidebar and this script talk with `postMessage`, same origin only:
 *
 *   sidebar → page: ready, selected, update_block, replace_field, entry_field,
 *                   dirty, saved, save_failed, reload, close
 *   page → sidebar: select, save
 */
(function () {
  const configEl = document.getElementById('brando-frontend-edit-config')
  if (!configEl || window.BrandoFrontendEdit) {
    return
  }

  const config = JSON.parse(configEl.textContent)
  const T = config.text
  const REOPEN_KEY = 'brando:frontend-edit:reopen'
  const SOURCE = 'brando:frontend-edit'

  // Lucide icons (square-pen, lock, link, circle-check), inlined because this
  // runs on the public site, which has no admin sprite.
  const ICONS = {
    pencil: '<path d="M12 3H5a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.375 2.625a1 1 0 0 1 3 3l-9.013 9.014a2 2 0 0 1-.853.505l-2.873.84a.5.5 0 0 1-.62-.62l.84-2.873a2 2 0 0 1 .506-.852z"/>',
    lock: '<rect width="18" height="11" x="3" y="11" rx="2" ry="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>',
    shared: '<path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/>',
    check: '<circle cx="12" cy="12" r="10"/><path d="m16 9-5.5 5.5L8 12"/>'
  }

  function icon(name) {
    return `<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name]}</svg>`
  }

  function escapeHTML(value) {
    return String(value ?? '').replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c])
  }

  function setCookie(on) {
    document.cookie = on
      ? `${config.cookie}=1; path=/; SameSite=Lax`
      : `${config.cookie}=; path=/; SameSite=Lax; max-age=0`
  }

  // The overlay lives in a shadow root: the site's CSS cannot restyle it and
  // its CSS cannot leak into the site.
  const host = document.createElement('brando-frontend-edit')
  const root = host.attachShadow({ mode: 'open' })
  root.innerHTML = `<style>${window.BrandoFrontendEditCSS || ''}</style>`
  document.body.appendChild(host)

  window.BrandoFrontendEdit = { host, config }

  if (!config.active) {
    const toggle = document.createElement('button')
    toggle.type = 'button'
    toggle.className = 'fe-toggle'
    toggle.setAttribute('data-testid', 'frontend-edit-toggle')
    toggle.innerHTML = `${icon('pencil')}<span>${escapeHTML(T.editPage)}</span>`
    toggle.addEventListener('click', () => {
      setCookie(true)
      window.location.reload()
    })
    root.appendChild(toggle)
    return
  }

  const BlockPatch = window.BrandoBlockPatch
  const manifest = { owners: {}, blocks: {}, fields: {}, ...(config.manifest || {}) }
  const editableCount = Object.keys(manifest.blocks).length + Object.keys(manifest.fields).length
  const isField = id => typeof id === 'string' && id.includes(':')

  // -- State ------------------------------------------------------------------

  const state = {
    registry: new Map(),
    elementToUid: new WeakMap(),
    fields: new Map(),
    hoverOccurrence: null,
    selectedOccurrence: null,
    registryBuiltAt: 0,
    hoverUid: null,
    selectedUid: null,
    sidebar: null,
    iframe: null,
    ready: false,
    dirty: false,
    pending: null,
    altHeld: false,
    overridesInserted: false
  }

  // -- Chrome -----------------------------------------------------------------

  const toolbar = document.createElement('div')
  toolbar.className = 'fe-toolbar'
  toolbar.setAttribute('data-testid', 'frontend-edit-toolbar')
  toolbar.innerHTML = `
    <div class="fe-toolbar-status">
      <span class="fe-toolbar-dot" aria-hidden="true"></span>
      <span class="fe-toolbar-title">${escapeHTML(T.editing)}</span>
      <span class="fe-toolbar-hint">${escapeHTML(editableCount ? T.hint : T.emptyHint)}</span>
    </div>
    <button type="button" class="fe-toolbar-done">${escapeHTML(T.done)}</button>`
  root.appendChild(toolbar)

  const toast = document.createElement('div')
  toast.className = 'fe-toast'
  toast.setAttribute('role', 'status')
  root.appendChild(toast)

  const hoverOutline = outline('is-hover')
  const selectedOutline = outline('is-selected')

  function outline(kind) {
    const el = document.createElement('div')
    el.className = `fe-outline ${kind}`
    el.innerHTML = '<div class="fe-label"></div>'
    root.appendChild(el)
    return el
  }

  toolbar.querySelector('.fe-toolbar-done').addEventListener('click', () => {
    guardUnsaved(() => {
      setCookie(false)
      window.location.reload()
    })
  })

  let toastTimer = null

  function showToast(message) {
    toast.innerHTML = `${icon('check')}<span>${escapeHTML(message)}</span>`
    toast.classList.add('is-visible')
    clearTimeout(toastTimer)
    toastTimer = setTimeout(() => toast.classList.remove('is-visible'), 2200)
  }

  // -- Blocks on the page -----------------------------------------------------

  function rebuildRegistry() {
    state.registry = BlockPatch.buildRegistry()
    state.elementToUid = new WeakMap()
    state.registry.forEach(({ uid, elements }) => {
      elements.forEach(({ element }) => state.elementToUid.set(element, uid))
    })
    state.fields = buildFieldRegistry()
    state.registryBuiltAt = Date.now()
  }

  // key → the places the field is marked: `{ start, end, kind }`, `kind` being
  // `E` (a printed value) or `W` (other markup showing the field).
  function buildFieldRegistry() {
    const fields = new Map()
    const iterator = document.createNodeIterator(document.body, NodeFilter.SHOW_COMMENT)
    const open = []
    let node

    while ((node = iterator.nextNode())) {
      const value = node.nodeValue.trim()
      const match = value.match(/^\[([+-]):([EW])<(.+)>\]$/)
      if (!match) continue

      const [, sign, kind, key] = match
      if (sign === '+') {
        open.push({ start: node, kind, key })
      } else {
        const index = open.findLastIndex(entry => entry.key === key && entry.kind === kind)
        if (index === -1) continue
        const [entry] = open.splice(index, 1)
        if (!fields.has(key)) fields.set(key, [])
        fields.get(key).push({ start: entry.start, end: node, kind })
      }
    }

    return fields
  }

  function occurrenceRange(occurrence) {
    if (!occurrence || !occurrence.start.isConnected || !occurrence.end.isConnected) return null
    const range = document.createRange()
    range.setStartAfter(occurrence.start)
    range.setEndBefore(occurrence.end)
    return range
  }

  // The element a field fills on its own, like `<h1>{title}</h1>`: the whole
  // element is the field's, not just its text. Null when it shares it.
  function soleHost(occurrence) {
    const parent = occurrence.start.parentNode
    if (!parent || parent.nodeType !== 1 || parent === document.body) return null

    let inside = false
    for (const node of parent.childNodes) {
      if (node === occurrence.start) inside = true
      else if (node === occurrence.end) inside = false
      else if (!inside && !(node.nodeType === 8 || (node.nodeType === 3 && !node.nodeValue.trim()))) return null
    }

    return parent
  }

  function occurrenceRects(occurrence) {
    const host = occurrence && occurrence.start.isConnected && soleHost(occurrence)
    if (host) return [host.getBoundingClientRect()]
    const range = occurrenceRange(occurrence)
    return range ? Array.from(range.getClientRects()) : []
  }

  // The marked field under the point, the smallest if they nest.
  function fieldAt(x, y) {
    let best = null

    state.fields.forEach((occurrences, key) => {
      if (!manifest.fields[key]) return

      occurrences.forEach(occurrence => {
        for (const rect of occurrenceRects(occurrence)) {
          if (x >= rect.left - 2 && x <= rect.right + 2 && y >= rect.top - 2 && y <= rect.bottom + 2) {
            const area = rect.width * rect.height
            if (!best || area < best.area) best = { key, occurrence, area }
            break
          }
        }
      })
    })

    return best
  }

  // The innermost block holding `node`: block elements nest inside their
  // parents', so the first one on the way up is the innermost.
  function blockUidFor(node) {
    let el = node && node.nodeType === 1 ? node : node && node.parentElement

    while (el && el !== document.body) {
      const uid = state.elementToUid.get(el)
      if (uid && manifest.blocks[uid]) {
        return uid
      }
      el = el.parentElement
    }

    return null
  }

  // What a click at the event would open: a marked field, or else the
  // block's target. `{ id, occurrence }`, or null.
  function findTarget(event) {
    const field = fieldAt(event.clientX, event.clientY)
    if (field) return { id: field.key, occurrence: field.occurrence }

    let uid = blockUidFor(event.target)

    // The site may have replaced elements since the registry was built.
    if (!uid && Date.now() - state.registryBuiltAt > 500) {
      rebuildRegistry()
      uid = blockUidFor(event.target)
    }

    return uid ? { id: manifest.blocks[uid].target, occurrence: null } : null
  }

  function blockRect(uid) {
    const block = state.registry.get(uid)
    if (!block || !block.start || !block.start.isConnected || !block.insertionPoint.isConnected) {
      return null
    }

    const range = document.createRange()
    range.setStartAfter(block.start)
    range.setEndBefore(block.insertionPoint)
    const rect = range.getBoundingClientRect()

    return rect.width || rect.height ? rect : null
  }

  function fieldRect(key, occurrence) {
    const occurrences = state.fields.get(key) || []
    const chosen = occurrences.includes(occurrence) ? occurrence : occurrences[0]
    if (!chosen) return null

    const host = chosen.start.isConnected && soleHost(chosen)
    const range = !host && occurrenceRange(chosen)
    const rect = host ? host.getBoundingClientRect() : range && range.getBoundingClientRect()
    return rect && (rect.width || rect.height) ? rect : null
  }

  function targetRect(id, occurrence) {
    if (!id) return null
    return isField(id) ? fieldRect(id, occurrence) : blockRect(id)
  }

  // For a field, its manifest entry carries `editable` and `shared` itself.
  function ownerOf(id) {
    if (isField(id)) return manifest.fields[id] || null
    const block = manifest.blocks[id]
    return block ? manifest.owners[block.owner] : null
  }

  function labelFor(id) {
    if (isField(id)) return (manifest.fields[id] && manifest.fields[id].label) || T.block
    const block = manifest.blocks[id]
    return (block && block.label) || T.block
  }

  function placeOutline(el, uid, text, occurrence = null) {
    const rect = targetRect(uid, occurrence)

    if (!rect) {
      el.classList.remove('is-visible')
      return
    }

    const owner = ownerOf(uid)
    const locked = !owner || !owner.editable
    const pad = 3

    // Kept inside the viewport, so a full-bleed block's outline and label show.
    const inset = 3
    const left = Math.max(rect.left - pad, inset)
    const right = Math.min(rect.right + pad, document.documentElement.clientWidth - inset)
    el.style.transform = `translate(${left}px, ${rect.top - pad}px)`
    el.style.width = `${Math.max(right - left, 0)}px`
    el.style.height = `${rect.height + pad * 2}px`
    el.classList.toggle('is-locked', locked)
    el.classList.toggle('is-inside', rect.top < 36)
    el.classList.add('is-visible')

    const label = el.querySelector('.fe-label')
    const note = locked ? T.notAllowed : owner.shared ? T.shared : null
    const prefix = locked ? icon('lock') : owner.shared ? icon('shared') : ''
    label.innerHTML = `${prefix}<span>${escapeHTML(text)}</span>${note ? `<span class="fe-label-note">· ${escapeHTML(note)}</span>` : ''}`
  }

  function render() {
    placeOutline(
      selectedOutline,
      state.selectedUid,
      `${T.editing} · ${labelFor(state.selectedUid)}`,
      state.selectedOccurrence
    )

    if (state.hoverUid && state.hoverUid !== state.selectedUid && !state.altHeld) {
      placeOutline(hoverOutline, state.hoverUid, labelFor(state.hoverUid), state.hoverOccurrence)
    } else {
      hoverOutline.classList.remove('is-visible')
    }
  }

  let frame = null

  function scheduleRender() {
    if (frame) return
    frame = requestAnimationFrame(() => {
      frame = null
      render()
    })
  }

  // -- Pointer ---------------------------------------------------------------

  function fromOverlay(event) {
    return event.composedPath().includes(host)
  }

  document.addEventListener(
    'mousemove',
    event => {
      if (fromOverlay(event)) {
        if (state.hoverUid) {
          state.hoverUid = null
          scheduleRender()
        }
        return
      }

      const target = state.altHeld ? null : findTarget(event)
      const id = target && target.id
      const occurrence = target && target.occurrence
      if (id !== state.hoverUid || occurrence !== state.hoverOccurrence) {
        state.hoverUid = id
        state.hoverOccurrence = occurrence
        scheduleRender()
      }
    },
    { passive: true }
  )

  document.addEventListener('mouseleave', () => {
    state.hoverUid = null
    scheduleRender()
  })

  // Clicks on blocks open them instead of following links or starting the
  // site's own handlers. Holding Alt (Option) uses the page as usual.
  document.addEventListener(
    'click',
    event => {
      if (fromOverlay(event) || event.altKey || event.button !== 0) return

      const target = findTarget(event)
      if (!target) return

      event.preventDefault()
      event.stopPropagation()

      const owner = ownerOf(target.id)
      if (!owner || !owner.editable) return

      select(target.id, target.occurrence)
    },
    true
  )

  window.addEventListener('keydown', event => {
    if (event.key === 'Alt') {
      state.altHeld = true
      scheduleRender()
    } else if (event.key === 'Escape' && state.sidebar && !dialogOpen()) {
      close()
    }
  })

  window.addEventListener('keyup', event => {
    if (event.key === 'Alt') {
      state.altHeld = false
      scheduleRender()
    }
  })

  window.addEventListener('blur', () => {
    state.altHeld = false
  })

  window.addEventListener('scroll', scheduleRender, { passive: true, capture: true })
  window.addEventListener('resize', scheduleRender, { passive: true })

  // -- Sidebar -----------------------------------------------------------------

  function editorUrl(id) {
    const param = isField(id) ? 'field' : 'uid'
    return `${config.editorUrl}?${param}=${encodeURIComponent(id)}`
  }

  function select(uid, occurrence = null) {
    if (uid === state.selectedUid && state.sidebar) {
      state.selectedOccurrence = occurrence
      scheduleRender()
      return
    }

    if (state.sidebar && state.dirty) {
      guardUnsaved(() => select(uid, occurrence), uid)
      return
    }

    state.selectedUid = uid
    state.selectedOccurrence = occurrence
    scheduleRender()

    if (state.sidebar && state.ready) {
      post(isField(uid) ? { type: 'select', field: uid } : { type: 'select', uid })
    } else {
      openSidebar(uid)
    }

    revealSelected()
  }

  function openSidebar(uid) {
    closeSidebar()
    dock(uid)

    const sidebar = document.createElement('aside')
    sidebar.className = 'fe-sidebar'
    sidebar.setAttribute('data-testid', 'frontend-edit-sidebar')
    sidebar.innerHTML = `
      <div class="fe-sidebar-loading"><div class="fe-spinner"></div><span>${escapeHTML(T.loading)}</span></div>`

    const iframe = document.createElement('iframe')
    iframe.title = T.editing
    iframe.src = editorUrl(uid)
    sidebar.prepend(iframe)
    root.appendChild(sidebar)

    state.sidebar = sidebar
    state.iframe = iframe
    state.ready = false
    state.dirty = false

    requestAnimationFrame(() => requestAnimationFrame(() => sidebar.classList.add('is-open')))
  }

  function closeSidebar() {
    if (state.sidebar) {
      state.sidebar.remove()
    }

    state.sidebar = null
    state.iframe = null
    state.ready = false
    state.dirty = false
  }

  function close() {
    guardUnsaved(() => {
      closeSidebar()
      state.selectedUid = null
      host.classList.remove('is-docked-left')
      scheduleRender()
    })
  }

  // Dock on the side the block is not on, so the sidebar does not cover it.
  function dock(uid) {
    const rect = targetRect(uid, state.selectedOccurrence)
    const width = Math.min(460, window.innerWidth - 48)
    let left = false

    if (rect) {
      const coveredRight = Math.max(0, rect.right - (window.innerWidth - width)) / (rect.width || 1)
      const coveredLeft = Math.max(0, width - rect.left) / (rect.width || 1)
      left = coveredRight > 0.5 && coveredLeft < coveredRight
    }

    host.classList.toggle('is-docked-left', left)
  }

  function revealSelected() {
    const rect = targetRect(state.selectedUid, state.selectedOccurrence)
    if (!rect) return

    if (rect.top < 0 || rect.top > window.innerHeight * 0.7) {
      window.scrollBy({ top: rect.top - window.innerHeight * 0.15, behavior: 'smooth' })
    }
  }

  function post(message) {
    if (state.iframe && state.iframe.contentWindow) {
      state.iframe.contentWindow.postMessage({ source: SOURCE, ...message }, window.location.origin)
    }
  }

  // -- Unsaved changes -------------------------------------------------------

  function dialogOpen() {
    return !!root.querySelector('.fe-dialog-backdrop')
  }

  // Runs `proceed` now, or after the editor has saved or discarded its
  // changes. Discarding reloads the page, which is the only way to put back
  // what the page showed before; `reopenUid` is opened again after it.
  function guardUnsaved(proceed, reopenUid = null) {
    if (!state.sidebar || !state.dirty) {
      proceed()
      return
    }

    if (dialogOpen()) return

    const backdrop = document.createElement('div')
    backdrop.className = 'fe-dialog-backdrop'
    backdrop.innerHTML = `
      <div class="fe-dialog" role="alertdialog" aria-modal="true" aria-labelledby="fe-dialog-title" aria-describedby="fe-dialog-body">
        <h2 id="fe-dialog-title">${escapeHTML(T.unsavedTitle)}</h2>
        <p id="fe-dialog-body">${escapeHTML(T.unsavedBody)}</p>
        <div class="fe-dialog-actions">
          <button type="button" class="fe-button" data-action="keep">${escapeHTML(T.keepEditing)}</button>
          <button type="button" class="fe-button is-danger" data-action="discard">${escapeHTML(T.discard)}</button>
          <button type="button" class="fe-button is-primary" data-action="save">${escapeHTML(T.save)}</button>
        </div>
      </div>`
    root.appendChild(backdrop)

    const dismiss = () => {
      backdrop.remove()
      window.removeEventListener('keydown', onKey, true)
    }

    const onKey = event => {
      if (event.key === 'Escape') {
        event.stopPropagation()
        dismiss()
      }
    }

    window.addEventListener('keydown', onKey, true)
    backdrop.querySelector('[data-action="save"]').focus()

    backdrop.addEventListener('click', event => {
      const action = event.target.closest('[data-action]')?.dataset.action
      if (event.target === backdrop || action === 'keep') {
        dismiss()
      } else if (action === 'discard') {
        dismiss()
        if (reopenUid) sessionStorage.setItem(REOPEN_KEY, reopenUid)
        state.dirty = false
        window.location.reload()
      } else if (action === 'save') {
        dismiss()
        state.pending = proceed
        post({ type: 'save' })
      }
    })
  }

  // -- Messages from the sidebar ---------------------------------------------

  function insertOverrides() {
    if (state.overridesInserted) return
    state.overridesInserted = true

    // Patched-in elements are never revealed by the site's scroll animations.
    const style = document.createElement('style')
    style.textContent = `
      [data-moonwalk], [data-moonwalk-run], [data-moonwalk-section], [data-moonwalk-children] > *, [b-section] {
        opacity: 1 !important; transform: none !important; visibility: visible !important;
      }`
    document.head.appendChild(style)
  }

  function replaceBetween(start, end, html) {
    if (!start.isConnected || start.parentNode !== end.parentNode) return
    let node = start.nextSibling
    while (node && node !== end) {
      const next = node.nextSibling
      node.remove()
      node = next
    }
    const template = document.createElement('template')
    template.innerHTML = html
    end.parentNode.insertBefore(template.content, end)
    BlockPatch.initializeMedia(end.parentNode)
  }

  // After a save, marked fields show what was saved: markup an `editable`
  // wraps can only be rendered by the page itself, so the page is fetched
  // again (in edit mode, with markers) and each marked place is replaced.
  async function refreshFields() {
    if (!state.fields.size) return

    try {
      const response = await fetch(window.location.href, { credentials: 'same-origin', headers: { accept: 'text/html' } })
      if (!response.ok) return
      const doc = new DOMParser().parseFromString(await response.text(), 'text/html')
      const fresh = new Map()
      const iterator = doc.createNodeIterator(doc.body, NodeFilter.SHOW_COMMENT)
      const open = []
      let node

      while ((node = iterator.nextNode())) {
        const match = node.nodeValue.trim().match(/^\[([+-]):([EW])<(.+)>\]$/)
        if (!match) continue
        const [, sign, kind, key] = match
        if (sign === '+') {
          open.push({ start: node, kind, key })
        } else {
          const index = open.findLastIndex(entry => entry.key === key && entry.kind === kind)
          if (index === -1) continue
          const [entry] = open.splice(index, 1)
          const range = doc.createRange()
          range.setStartAfter(entry.start)
          range.setEndBefore(node)
          const holder = doc.createElement('div')
          holder.appendChild(range.cloneContents())
          const id = `${kind}:${key}`
          if (!fresh.has(id)) fresh.set(id, [])
          fresh.get(id).push(holder.innerHTML)
        }
      }

      rebuildRegistry()
      state.fields.forEach((occurrences, key) => {
        occurrences.forEach((occurrence, index) => {
          const html = (fresh.get(`${occurrence.kind}:${key}`) || [])[index]
          if (html !== undefined) replaceBetween(occurrence.start, occurrence.end, html)
        })
      })
      rebuildRegistry()
      BlockPatch.announcePatch('field', [], null, 'frontend-edit')
      scheduleRender()
    } catch (_error) {
      // The page keeps what it shows; a reload brings it up to date.
    }
  }

  const handlers = {
    ready({ target }) {
      state.ready = true
      state.sidebar?.querySelector('.fe-sidebar-loading')?.classList.add('is-done')
      if (target && target !== state.selectedUid && (manifest.blocks[target] || manifest.fields[target])) {
        state.selectedUid = target
        state.selectedOccurrence = null
      }
      scheduleRender()
    },

    selected({ target }) {
      if (target !== state.selectedUid) state.selectedOccurrence = null
      state.selectedUid = target
      scheduleRender()
      revealSelected()
    },

    update_block({ uid, rendered_html, has_children }) {
      insertOverrides()
      if (!state.registry.has(uid)) rebuildRegistry()

      const elements = BlockPatch.patchBlock(state.registry, { uid, rendered_html, has_children })
      if (!elements) return

      rebuildRegistry()
      BlockPatch.announcePatch('block', elements, uid, 'frontend-edit')
      scheduleRender()
    },

    replace_field({ key, html }) {
      insertOverrides()
      const parent = BlockPatch.replaceField(key, html)
      if (!parent) return

      rebuildRegistry()
      BlockPatch.announcePatch('field', [parent], null, 'frontend-edit')
      scheduleRender()
    },

    // A printed field value changed: every place it is printed shows it.
    entry_field({ key, html }) {
      rebuildRegistry()
      ;(state.fields.get(key) || [])
        .filter(occurrence => occurrence.kind === 'E')
        .forEach(occurrence => replaceBetween(occurrence.start, occurrence.end, html))
      rebuildRegistry()
      scheduleRender()
    },

    dirty({ dirty }) {
      state.dirty = !!dirty
    },

    saved() {
      state.dirty = false
      showToast(T.saved)
      refreshFields()

      const proceed = state.pending
      state.pending = null
      if (proceed) proceed()
    },

    save_failed() {
      state.pending = null
    },

    // Someone else saved the entry: start over from what is saved now.
    reload({ uid }) {
      if (uid) sessionStorage.setItem(REOPEN_KEY, uid)
      state.dirty = false
      window.location.reload()
    },

    close() {
      close()
    }
  }

  window.addEventListener('message', event => {
    if (
      event.origin !== window.location.origin ||
      !state.iframe ||
      event.source !== state.iframe.contentWindow ||
      !event.data ||
      event.data.source !== SOURCE
    ) {
      return
    }

    const handler = handlers[event.data.type]
    if (handler) handler(event.data)
  })

  window.addEventListener('beforeunload', event => {
    if (state.dirty) {
      event.preventDefault()
      event.returnValue = ''
    }
  })

  // -- Start -------------------------------------------------------------------

  rebuildRegistry()

  const reopen = sessionStorage.getItem(REOPEN_KEY)
  sessionStorage.removeItem(REOPEN_KEY)

  if (reopen && manifest.fields[reopen]) {
    select(reopen)
  } else if (reopen && manifest.blocks[reopen]) {
    select(manifest.blocks[reopen].target)
  }
})()
