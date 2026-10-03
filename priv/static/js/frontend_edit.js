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
 * The sidebar and this script talk with `postMessage`, same origin only:
 *
 *   sidebar → page: ready, update_block, replace_field, dirty, saved, close
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

  const ICONS = {
    pencil:
      '<path stroke-linecap="round" stroke-linejoin="round" d="m16.862 4.487 1.687-1.688a1.875 1.875 0 1 1 2.652 2.652L10.582 16.07a4.5 4.5 0 0 1-1.897 1.13L6 18l.8-2.685a4.5 4.5 0 0 1 1.13-1.897l8.932-8.931Zm0 0L19.5 7.125M18 14v4.75A2.25 2.25 0 0 1 15.75 21H5.25A2.25 2.25 0 0 1 3 18.75V8.25A2.25 2.25 0 0 1 5.25 6H10" />',
    lock:
      '<path stroke-linecap="round" stroke-linejoin="round" d="M16.5 10.5V6.75a4.5 4.5 0 1 0-9 0v3.75m-.75 11.25h10.5a2.25 2.25 0 0 0 2.25-2.25v-6.75a2.25 2.25 0 0 0-2.25-2.25H6.75a2.25 2.25 0 0 0-2.25 2.25v6.75a2.25 2.25 0 0 0 2.25 2.25Z" />',
    shared:
      '<path stroke-linecap="round" stroke-linejoin="round" d="M13.19 8.688a4.5 4.5 0 0 1 1.242 7.244l-4.5 4.5a4.5 4.5 0 0 1-6.364-6.364l1.757-1.757m13.35-.622 1.757-1.757a4.5 4.5 0 0 0-6.364-6.364l-4.5 4.5a4.5 4.5 0 0 0 1.242 7.244" />',
    check:
      '<path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75 11.25 15 15 9.75M21 12a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z" />'
  }

  function icon(name) {
    return `<svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.8" stroke="currentColor" aria-hidden="true">${ICONS[name]}</svg>`
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
  const manifest = config.manifest || { owners: {}, blocks: {} }
  const editableCount = Object.keys(manifest.blocks).length

  // -- State ------------------------------------------------------------------

  const state = {
    registry: new Map(),
    elementToUid: new WeakMap(),
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
    state.registryBuiltAt = Date.now()
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

  function findTarget(node) {
    let uid = blockUidFor(node)

    // The site may have replaced elements since the registry was built.
    if (!uid && Date.now() - state.registryBuiltAt > 500) {
      rebuildRegistry()
      uid = blockUidFor(node)
    }

    return uid ? manifest.blocks[uid].target : null
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

  function ownerOf(uid) {
    const block = manifest.blocks[uid]
    return block ? manifest.owners[block.owner] : null
  }

  function labelFor(uid) {
    const block = manifest.blocks[uid]
    return (block && block.label) || T.block
  }

  function placeOutline(el, uid, text) {
    const rect = uid && blockRect(uid)

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
    placeOutline(selectedOutline, state.selectedUid, `${T.editing} · ${labelFor(state.selectedUid)}`)

    if (state.hoverUid && state.hoverUid !== state.selectedUid && !state.altHeld) {
      placeOutline(hoverOutline, state.hoverUid, labelFor(state.hoverUid))
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

      const target = state.altHeld ? null : findTarget(event.target)
      if (target !== state.hoverUid) {
        state.hoverUid = target
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

      const target = findTarget(event.target)
      if (!target) return

      event.preventDefault()
      event.stopPropagation()

      const owner = ownerOf(target)
      if (!owner || !owner.editable) return

      select(target)
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

  function editorUrl(uid) {
    return `${config.editorUrl}?uid=${encodeURIComponent(uid)}`
  }

  function select(uid) {
    if (uid === state.selectedUid && state.sidebar) {
      return
    }

    if (state.sidebar && state.dirty) {
      guardUnsaved(() => select(uid), uid)
      return
    }

    state.selectedUid = uid
    scheduleRender()

    if (state.sidebar && state.ready) {
      post({ type: 'select', uid })
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
    const rect = blockRect(uid)
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
    const rect = blockRect(state.selectedUid)
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

  const handlers = {
    ready({ target }) {
      state.ready = true
      state.sidebar?.querySelector('.fe-sidebar-loading')?.classList.add('is-done')
      if (target && target !== state.selectedUid && manifest.blocks[target]) {
        state.selectedUid = target
      }
      scheduleRender()
    },

    selected({ target }) {
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

    dirty({ dirty }) {
      state.dirty = !!dirty
    },

    saved() {
      state.dirty = false
      showToast(T.saved)

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

  if (reopen && manifest.blocks[reopen]) {
    select(manifest.blocks[reopen].target)
  }
})()
