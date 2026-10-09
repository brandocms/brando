<script>
  import { onMount, onDestroy } from 'svelte'
  import { Editor, posToDOMRect } from '@tiptap/core'
  import { closeHistory } from '@tiptap/pm/history'
  import { Fragment, Slice } from '@tiptap/pm/model'
  import { computePosition, autoUpdate, offset, flip, shift } from '@floating-ui/dom'
  import { createExtensions, removeTextFormatting } from './createExtensions'
  import { resolveCapabilities, normalizeStyles, headingLevelForElement } from './config'
  import { defaultLabels } from './labels'
  import { isButtonLink } from './extensions/Link'
  import { defaultFootnoteLabels, renumberFootnotes } from './extensions/Footnote'
  import HTMLInputParser from './extensions/PasteCleaner/HTMLInputParser'
  import Icon from '../Icon/Icon.svelte'
  import { captureRange, mapRange } from './selection'
  import { proposalExtension, proposalKey } from './aiProposal'

  let { content = '', extensions, styles = '[]', onFocus, onBlur, onToggleLink, onToggleButton, onEditorCreated, tiptapInput,
    footnotes = false, footnoteLabels = defaultFootnoteLabels, onOpenFootnote, labels: providedLabels = {}, accessibility = {},
    aiEnabled = false, onGenerateAi, onCancelAi, typography = {}, labelMode = 'compact', canAddNote, onAddNote } = $props()
  const labels = $derived({ ...defaultLabels, ...providedLabels })
  const capabilities = $derived(resolveCapabilities(extensions))
  const parsedStyles = $derived(normalizeStyles(styles))
  const has = key => capabilities.includes(key)
  let element, shell, typeMenu, listMenu, moreMenu, anchorMenu, aiMenu, noteBubble, stopNoteBubble
  let toolbar = $state.raw(null)
  let editor = $state.raw(null)
  let revision = $state(0)
  let expanded = $state(false)
  let currentMenu = $state('')
  let notice = $state('')
  let anchorId = $state('')
  let anchorError = $state('')
  let aiMode = $state('rewrite')
  let instruction = $state('')
  let pending = null, anchorRange = null, menuTrigger = null, pressedMenu = '', stopPositioning, inertSiblings = [], resumeOverlay = false, menuCleanups = []
  const id = $derived(`${tiptapInput?.id || 'tiptap'}-controls`)
  const active = $derived.by(() => {
    revision
    if (!editor) return {}
    const marks = Object.fromEntries(['bold', 'italic', 'subscript', 'superscript', 'link', 'jumpAnchor', 'blockquote', 'bulletList', 'orderedList', 'underline', 'strike', 'code', 'codeBlock'].map(name => [name, editor.isActive(name)]))
    return { ...marks, level: editor.isActive('heading') ? editor.getAttributes('heading').level : null, linkAttrs: editor.getAttributes('link'), color: editor.getAttributes('textStyle').color || '', styles: Object.fromEntries(parsedStyles.map(style => [style.key, style.mode === 'mark' ? editor.isActive(style.markName) : editor.isActive(style.element === 'p' ? 'paragraph' : 'heading', { class: style.className, ...(style.element === 'p' ? {} : { level: headingLevelForElement(style.element) }) })])), canUndo: editor.can().undo(), canRedo: editor.can().redo(), editable: editor.isEditable }
  })
  const wordCount = $derived.by(() => { revision; return expanded && editor ? editor.getText().trim().split(/\s+/).filter(Boolean).length : 0 })
  const typeLabel = $derived(labelMode === 'icon' ? '¶' : active.level ? labelMode === 'full' ? labels.heading.replace('%{level}', active.level) : `H${active.level}` : labelMode === 'full' ? labels.paragraph : '¶')
  const more = $derived([
    ['sub', 'subscript', 'toggleSubscript'], ['sup', 'superscript', 'toggleSuperscript'], ['blockquote', 'blockquote', 'toggleBlockquote'],
    ['underline', 'underline', 'toggleUnderline'], ['strike', 'strike', 'toggleStrike'], ['code', 'code', 'toggleCode'], ['codeBlock', 'codeBlock', 'toggleCodeBlock'],
  ].filter(([key]) => has(key)))
  function closeMenus() { [typeMenu, listMenu, moreMenu, anchorMenu, aiMenu].forEach(menu => { if (menu?.matches(':popover-open')) menu.hidePopover() }); stopPositioning?.(); stopPositioning = null; currentMenu = '' }
  // Pressing a trigger light-dismisses its open popover before the click
  // arrives, so the click would reopen it. Remember what was open at the press.
  function showMenu(menu, trigger, name) {
    const wasOpen = menu.matches(':popover-open') || pressedMenu === name
    pressedMenu = ''
    closeMenus()
    if (wasOpen) return
    menuTrigger = trigger; currentMenu = name; menu.showPopover()
    stopPositioning = autoUpdate(trigger, menu, () => computePosition(trigger, menu, { strategy: 'fixed', placement: 'bottom-start', middleware: [offset(6), flip(), shift({ padding: 8 })] }).then(({ x, y }) => Object.assign(menu.style, { left: `${x}px`, top: `${y}px` })))
    menu.querySelector('input, button:not(:disabled), select')?.focus()
  }
  function menuKeys(event) {
    if (event.key === 'Escape') { event.preventDefault(); event.stopPropagation(); closeMenus(); menuTrigger?.focus(); return }
    if (!['ArrowDown', 'ArrowUp', 'Home', 'End'].includes(event.key) || event.target.matches('input, select')) return
    const buttons = [...event.currentTarget.querySelectorAll('button:not(:disabled)')]
    const index = buttons.indexOf(document.activeElement)
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? buttons.length - 1 : (index + (event.key === 'ArrowDown' ? 1 : -1) + buttons.length) % buttons.length
    event.preventDefault(); buttons[next]?.focus()
  }
  function toolbarFocus(event) { if (!event.target.matches('button')) return; [...toolbar.querySelectorAll(':scope > button, :scope > .menu-item-group > button')].forEach(button => button.tabIndex = button === event.target ? 0 : -1) }
  function toolbarKeys(event) {
    if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key) || currentMenu) return
    const buttons = [...toolbar.querySelectorAll(':scope > button:not(:disabled), :scope > .menu-item-group > button:not(:disabled)')]
    const index = buttons.indexOf(event.target)
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? buttons.length - 1 : (index + (event.key === 'ArrowRight' ? 1 : -1) + buttons.length) % buttons.length
    event.preventDefault(); buttons[next]?.focus()
  }
  function colorHex(value) {
    if (/^#[0-9a-f]{6}$/i.test(value)) return value
    if (/^#[0-9a-f]{3}$/i.test(value)) return '#' + [...value.slice(1)].map(c => c + c).join('')
    const rgb = value?.match(/^rgba?\(\s*(\d+)\D+(\d+)\D+(\d+)/)
    return rgb ? '#' + rgb.slice(1, 4).map(v => Math.min(255, Number(v)).toString(16).padStart(2, '0')).join('') : '#272b2a'
  }
  function command(name, ...args) { closeMenus(); if (editor.isEditable) editor.chain().focus()[name](...args).run() }
  function setParagraph(level = null) { command(level ? 'setHeading' : 'setParagraph', ...(level ? [{ level }] : [])) }
  function applyStyle(style) {
    closeMenus()
    if (style.mode === 'mark') return command('toggleMark', style.markName)
    const node = style.element === 'p' ? 'paragraph' : 'heading'
    const chain = editor.chain().focus()
    if (node === 'paragraph') chain.setParagraph()
    else chain.setHeading({ level: headingLevelForElement(style.element) })
    chain.updateAttributes(node, { class: style.className }).run()
  }
  function resetStyle() { closeMenus(); editor.chain().focus().resetAttributes('paragraph', 'class').resetAttributes('heading', 'class').run() }
  function openLink(button = false) {
    closeMenus()
    if (expanded) { shell.hidePopover(); shell.removeAttribute('popover'); releaseInert(); resumeOverlay = true }
    const attrs = editor.getAttributes('link')
    const callback = button ? onToggleButton : onToggleLink
    callback?.(attrs.href || '', attrs.target ?? null, attrs['data-identifier-id'] || null)
  }
  function openAnchor(event) { anchorRange = captureRange(editor); anchorId = editor.getAttributes('jumpAnchor').id || ''; anchorError = ''; showMenu(anchorMenu, event.currentTarget, 'anchor') }
  function applyAnchor() {
    const value = anchorId.trim()
    const old = editor.getAttributes('jumpAnchor').id
    const scope = element.closest('.blocks-wrapper') || document
    const duplicates = [...scope.querySelectorAll('[id]')].some(node => node.id === value && (!element.contains(node) || old !== value))
    if (!value || /[\s\u0000-\u001f\u007f]/u.test(value) || duplicates || !anchorRange?.valid) { anchorError = labels.anchorInvalid; return }
    editor.chain().focus().setTextSelection({ from: anchorRange.from, to: anchorRange.to }).extendMarkRange('jumpAnchor').setJumpAnchor({ id: value }).run(); closeMenus()
  }
  function releaseInert() { inertSiblings.forEach(node => node.inert = false); inertSiblings = [] }
  function makeInert() { let node = shell; while (node.parentElement && node.parentElement !== document.documentElement) { [...node.parentElement.children].filter(sibling => sibling !== node && !sibling.inert).forEach(sibling => { sibling.inert = true; inertSiblings.push(sibling) }); node = node.parentElement } }
  function toggleExpanded() {
    closeMenus()
    if (expanded) { shell.hidePopover(); shell.removeAttribute('popover'); releaseInert(); expanded = false }
    else { expanded = true; shell.setAttribute('popover', 'manual'); shell.showPopover(); makeInert() }
    queueMicrotask(() => {
      const first = toolbar?.querySelector('button:not(:disabled)')
      toolbar?.querySelectorAll('button').forEach(button => button.tabIndex = button === first ? 0 : -1)
    })
    editor.commands.focus()
  }
  function shellKeys(event) {
    if (!expanded) return
    if (event.key === 'Escape' && !currentMenu) { event.preventDefault(); event.stopPropagation(); toggleExpanded() }
    if (event.key === 'Tab' && !event.defaultPrevented && !currentMenu) {
      const controls = [...shell.querySelectorAll('button:not(:disabled), [contenteditable="true"], input, select')].filter(node => node.getClientRects().length && node.tabIndex >= 0)
      if (event.shiftKey && event.target === controls[0]) { event.preventDefault(); controls.at(-1)?.focus() }
      else if (!event.shiftKey && (event.target === controls.at(-1) || controls.at(-1)?.contains(event.target))) { event.preventDefault(); controls[0]?.focus() }
    }
  }
  export function linkClosed() { if (resumeOverlay) { resumeOverlay = false; shell.setAttribute('popover', 'manual'); shell.showPopover(); makeInert() }; editor?.commands.focus() }
  export function showError(message = labels.linkFailed) { notice = message }
  function renderProposal() { editor.view.dispatch(editor.state.tr.setMeta(proposalKey, pending ? { id: pending.id, pos: Math.min(pending.range.to, editor.state.doc.content.size), status: pending.status, text: pending.text, error: pending.error } : null).setMeta('addToHistory', false)) }
  function discardProposal() { if (pending?.status === 'pending') onCancelAi?.(pending.id); pending = null; renderProposal(); editor.commands.focus() }
  function generate() {
    closeMenus()
    if (!aiEnabled || !editor.isEditable) return
    if (pending) discardProposal()
    const selection = editor.state.selection
    const range = aiMode === 'continue' ? { from: selection.to, to: selection.to } : selection.empty ? { from: 0, to: editor.state.doc.content.size } : selection
    pending = { id: crypto.randomUUID(), range: captureRange(editor, range), status: 'pending', mode: aiMode, text: '', error: null }
    const selectedText = aiMode === 'continue' ? editor.state.doc.textBetween(Math.max(0, range.to - 4000), range.to, '\n') : editor.state.doc.textBetween(range.from, range.to, '\n')
    renderProposal()
    onGenerateAi?.({ request_id: pending.id, mode: aiMode, instruction, selection: selectedText })
  }
  export function openAi() { if (aiEnabled) showMenu(aiMenu, toolbar.querySelector('[data-ai-trigger]'), 'ai') }
  export function receiveAi(payload) {
    if (!pending || pending.id !== payload.request_id) return
    pending.status = payload.error ? 'error' : 'ready'
    pending.text = payload.text || ''
    pending.error = !pending.range.valid ? labels.changed : payload.error ? labels.aiFailed : null
    renderProposal()
  }
  // The editor's changes to the suggestion before accepting it. The panel
  // keeps its textarea, so this does not redraw it.
  function editProposal(text) { if (pending?.status === 'ready') pending.text = text }
  function acceptProposal() {
    if (!pending || pending.status !== 'ready' || !pending.range.valid || !editor.isEditable) return
    const { range, text } = pending
    const lines = text.split(/\n+/).filter(Boolean)
    if (!lines.length) { pending.error = labels.aiFailed; renderProposal(); return }
    const from = editor.state.doc.resolve(range.from), to = editor.state.doc.resolve(range.to)
    const inline = from.parent.inlineContent && to.parent.inlineContent
    const replacement = lines.length === 1 && inline
      ? new Slice(Fragment.from(editor.schema.text(lines[0], from.marks())), 0, 0)
      : new Slice(Fragment.fromArray(lines.map(line => editor.schema.nodes.paragraph.create(null, editor.schema.text(line)))), inline ? 1 : 0, inline ? 1 : 0)
    pending = null; renderProposal()
    editor.chain().focus().command(({ tr }) => { closeHistory(tr); tr.replaceRange(range.from, range.to, replacement); return true }).run()
    editor.view.dispatch(closeHistory(editor.state.tr).setMeta('addToHistory', false))
    notice = labels.aiAccepted
  }
  // "Add note" floats over a text selection in block-owned rich text, while
  // the entry's notes are on (`assets/src/Notes`).
  function hideNoteBubble() { if (noteBubble && !noteBubble.hidden) noteBubble.hidden = true; stopNoteBubble?.(); stopNoteBubble = null }
  function updateNoteBubble() {
    if (!noteBubble || !editor || editor.isDestroyed) return
    const { from, to, empty } = editor.state.selection
    if (empty || expanded || !editor.isEditable || !editor.view.hasFocus() || !canAddNote?.() || !editor.state.doc.textBetween(from, to, ' ').trim()) { hideNoteBubble(); return }
    const reference = { getBoundingClientRect: () => posToDOMRect(editor.view, editor.state.selection.from, editor.state.selection.to), contextElement: editor.view.dom }
    noteBubble.hidden = false
    stopNoteBubble?.()
    stopNoteBubble = autoUpdate(reference, noteBubble, () => computePosition(reference, noteBubble, { strategy: 'fixed', placement: 'top', middleware: [offset(8), flip(), shift({ padding: 8 })] }).then(({ x, y }) => Object.assign(noteBubble.style, { left: `${x}px`, top: `${y}px` })))
  }
  function addNote() {
    if (!editor || editor.state.selection.empty) return
    const { from, to } = editor.state.selection
    hideNoteBubble()
    onAddNote?.({ from, to, text: editor.state.doc.textBetween(from, to, ' ') })
  }
  onMount(() => {
    editor = new Editor({
      element, content,
      extensions: [...createExtensions({ capabilities, styles: parsedStyles, footnoteLabels, onOpenFootnote, placeholder: labels.placeholder, typography }), proposalExtension({ labels, accept: acceptProposal, discard: discardProposal, retry: generate, edit: editProposal })],
      editorProps: {
        attributes: { role: 'textbox', 'aria-multiline': 'true', ...accessibility },
        transformPastedHTML: html => new HTMLInputParser({ capabilities, styles: parsedStyles, scope: element.closest('.blocks-wrapper') || element, onWarning: key => notice = labels[key] }).prepareHTML(html),
        handleKeyDown: (_view, event) => {
          if (event.altKey && event.key === 'F10') { toolbar.querySelector('button:not(:disabled)')?.focus(); return true }
          // ⌥⌘M / Ctrl+Alt+M: add a note on the selected text.
          if (event.altKey && (event.metaKey || event.ctrlKey) && event.code === 'KeyM' && canAddNote?.() && !editor.state.selection.empty) { addNote(); return true }
          return false
        },
      },
      onFocus: payload => { onFocus?.(payload); updateNoteBubble() },
      onBlur: () => { hideNoteBubble(); onBlur?.() },
      onSelectionUpdate: () => updateNoteBubble(),
      onUpdate: ({ editor: current }) => { tiptapInput.value = current.getHTML(); tiptapInput.dispatchEvent(new Event('input', { bubbles: true })); renumberFootnotes(element) },
      onTransaction: ({ transaction }) => {
        revision++
        if (transaction.getMeta('brando:replacement')) { anchorRange = null; if (pending) { pending.range.valid = false; pending.error = labels.changed; queueMicrotask(renderProposal) } }
        anchorRange = mapRange(anchorRange, transaction)
        if (pending && transaction.docChanged) {
          pending.range = mapRange(pending.range, transaction)
          if (!pending.range.valid && !pending.error) { pending.error = labels.changed; queueMicrotask(() => { if (pending && !editor.isDestroyed) renderProposal() }) }
        }
      },
    })
    onEditorCreated?.(editor)
    queueMicrotask(() => {
      if (editor.isDestroyed) return
      for (const menu of [typeMenu, listMenu, moreMenu, anchorMenu, aiMenu]) {
        const onToggle = () => { if (![typeMenu, listMenu, moreMenu, anchorMenu, aiMenu].some(node => node?.matches(':popover-open'))) { currentMenu = ''; stopPositioning?.(); stopPositioning = null } }
        menu.addEventListener('toggle', onToggle)
        menuCleanups.push(() => menu.removeEventListener('toggle', onToggle))
      }
    })
  })
  onDestroy(() => { menuCleanups.forEach(cleanup => cleanup()); stopPositioning?.(); stopNoteBubble?.(); releaseInert(); if (pending?.status === 'pending') onCancelAi?.(pending.id); editor?.destroy() })
</script>

<div bind:this={shell} class="tiptap-editor-shell" class:expanded role={expanded ? 'dialog' : 'group'} aria-modal={expanded ? 'true' : undefined} aria-label={accessibility['aria-label'] || labels.toolbar} onkeydown={shellKeys}>
  {#if expanded}
    <div class="tiptap-expanded-header">
      <div class="tiptap-expanded-heading">
        <span class="tiptap-expanded-icon" aria-hidden="true"><Icon name="file-text" /></span>
        <div class="tiptap-expanded-heading-copy"><h2>{accessibility['aria-label'] || labels.toolbar}</h2><p>{labels.expandedEditing}</p></div>
      </div>
      <button type="button" class="tiptap-expanded-done" onclick={toggleExpanded}><Icon name="minimize-2" />{labels.collapse}</button>
    </div>
  {/if}
  {#if editor}
    <div bind:this={toolbar} class="tiptap-menu" role="toolbar" tabindex="-1" aria-label={labels.toolbar} onkeydown={toolbarKeys} onfocusin={toolbarFocus} onpointerdowncapture={() => { pressedMenu = currentMenu }} onclick={() => { pressedMenu = '' }}>
      <button type="button" class="menu-item tiptap-type-control" class:tiptap-type-pilcrow={typeLabel === '¶'} aria-label={labels.styles} data-tooltip={labels.styles} aria-expanded={currentMenu === 'type'} aria-controls={`${id}-types`} disabled={!active.editable} onclick={event => showMenu(typeMenu, event.currentTarget, 'type')}><span>{typeLabel}</span><Icon name="chevron-down" /></button>
      {#if has('bold')}<button type="button" class="menu-item" aria-label={labels.bold} data-tooltip={`${labels.bold} · ⌘/Ctrl B`} aria-pressed={active.bold} disabled={!active.editable} tabindex="-1" onclick={() => command('toggleBold')}><Icon name="bold" /></button>{/if}
      {#if has('italic')}<button type="button" class="menu-item" aria-label={labels.italic} data-tooltip={`${labels.italic} · ⌘/Ctrl I`} aria-pressed={active.italic} disabled={!active.editable} tabindex="-1" onclick={() => command('toggleItalic')}><Icon name="italic" /></button>{/if}
      {#if has('list') || has('orderedList')}
        <div class="menu-item-group">
          <button type="button" class="menu-item" aria-label={active.orderedList || !has('list') ? labels.orderedList : labels.list} aria-pressed={active.bulletList || active.orderedList} disabled={!active.editable} tabindex="-1" onclick={() => command(active.orderedList || !has('list') ? 'toggleOrderedList' : 'toggleBulletList')}>{#if active.orderedList}<span aria-hidden="true" class="tiptap-list-number">1.</span>{:else}<Icon name="list" />{/if}</button>
          <button type="button" class="menu-item tiptap-disclosure" aria-label={labels.listTypes} data-tooltip={labels.listTypes} aria-expanded={currentMenu === 'list'} aria-controls={`${id}-lists`} tabindex="-1" disabled={!active.editable} onclick={event => showMenu(listMenu, event.currentTarget, 'list')}><Icon name="chevron-down" /></button>
        </div>
      {/if}
      {#if has('link')}<button type="button" class="menu-item" aria-label={labels.link} data-tooltip={labels.link} aria-pressed={active.link && !isButtonLink(active.linkAttrs)} disabled={!active.editable} tabindex="-1" onclick={() => openLink()}><Icon name="link" /></button>{/if}
      {#if has('button')}<button type="button" class="menu-item" aria-label={labels.button} data-tooltip={labels.button} aria-pressed={isButtonLink(active.linkAttrs)} disabled={!active.editable} tabindex="-1" onclick={() => openLink(true)}><Icon name="grid-2x2-plus" /></button>{/if}
      {#if footnotes}<button type="button" class="menu-item tiptap-add-footnote" aria-label={footnoteLabels.add} data-tooltip={footnoteLabels.add} disabled={!active.editable} tabindex="-1" onclick={() => onOpenFootnote?.(null)}><span aria-hidden="true">a¹</span></button>{/if}
      {#if has('jumpAnchor')}<button type="button" class="menu-item" aria-label={labels.anchor} data-tooltip={labels.anchor} aria-pressed={active.jumpAnchor} disabled={!active.editable} tabindex="-1" onclick={openAnchor}><Icon name="anchor" /></button>{/if}
      {#if more.length || ['horizontalRule', 'align', 'color', 'unsetMarks'].some(has)}<button type="button" class="menu-item" aria-label={labels.more} data-tooltip={labels.more} aria-expanded={currentMenu === 'more'} aria-controls={`${id}-more`} disabled={!active.editable} tabindex="-1" onclick={event => showMenu(moreMenu, event.currentTarget, 'more')}><Icon name="ellipsis" /></button>{/if}
      <button type="button" class="menu-item tiptap-undo" aria-label={labels.undo} data-tooltip={`${labels.undo} · ⌘/Ctrl Z`} disabled={!active.editable || !active.canUndo} tabindex="-1" onclick={() => command('undo')}><Icon name="undo-2" /></button>
      <button type="button" class="menu-item" aria-label={labels.redo} data-tooltip={`${labels.redo} · ⌘/Ctrl ⇧ Z`} disabled={!active.editable || !active.canRedo} tabindex="-1" onclick={() => command('redo')}><Icon name="redo-2" /></button>
      {#if aiEnabled}<button type="button" class="menu-item tiptap-ai-trigger" data-ai-trigger aria-label={labels.ai} data-tooltip={labels.ai} disabled={!active.editable} tabindex="-1" onclick={openAi}><Icon name="sparkles" /></button>{/if}
      {#if !expanded}<button type="button" class="menu-item" aria-label={labels.expand} data-tooltip={labels.expand} tabindex={active.editable ? -1 : 0} onclick={toggleExpanded}><Icon name="maximize-2" /></button>{/if}
    </div>
  {/if}
  <div class="tiptap-writing-area"><div bind:this={element} class="tiptap-document"></div></div>
  {#if editor && active.link}
    <div class="tiptap-link-preview"><span>{active.linkAttrs.href}</span><button type="button" disabled={!active.editable} onclick={() => openLink(isButtonLink(active.linkAttrs))}>{labels.edit}</button><button type="button" disabled={!active.editable} onclick={() => command('unsetLink')}>{labels.remove}</button><a href={active.linkAttrs.href} target="_blank" rel="noopener noreferrer">{labels.open}</a></div>
  {/if}
  {#if notice || expanded}<div class="tiptap-status" role="status">{#if expanded}<span class="tiptap-return-hint"><kbd>Esc</kbd>{labels.returnToForm}</span>{/if}{#if notice}<span class="tiptap-notice">{notice}</span>{/if}{#if expanded && editor}<span class="tiptap-word-count">{labels.words.replace('%{count}', wordCount)}</span>{/if}</div>{/if}

  <div bind:this={noteBubble} class="tiptap-note-bubble" hidden>
    <button type="button" onpointerdown={event => event.preventDefault()} onclick={addNote} title={`${labels.addNote} · ⌥⌘M`}><Icon name="message-square-plus" />{labels.addNote}</button>
  </div>

  <div bind:this={typeMenu} id={`${id}-types`} popover="auto" class="tiptap-popover style-dropdown" role="menu" tabindex="-1" aria-label={labels.styles} onkeydown={menuKeys}>
    <button type="button" role="menuitem" onclick={() => setParagraph()}>{labels.paragraph}</button>
    {#each [1, 2, 3, 4, 5, 6].filter(level => has(`h${level}`)) as level}<button type="button" role="menuitem" class:active={active.level === level} onclick={() => setParagraph(level)}>{labels.heading.replace('%{level}', level)}</button>{/each}
    {#each parsedStyles as style (style.key)}<button type="button" role="menuitemcheckbox" aria-checked={!!active.styles?.[style.key]} class:active={active.styles?.[style.key]} onclick={() => applyStyle(style)}>{#if style.icon}<Icon name={style.icon} />{/if}{style.label}</button>{/each}
    {#if parsedStyles.length}<hr /><button type="button" role="menuitem" onclick={resetStyle}>{labels.resetStyle}</button>{/if}
  </div>
  <div bind:this={listMenu} id={`${id}-lists`} popover="auto" class="tiptap-popover" role="menu" tabindex="-1" aria-label={labels.listTypes} onkeydown={menuKeys}>
    {#if has('list')}<button type="button" role="menuitem" onclick={() => command('toggleBulletList')}>{labels.list}</button>{/if}
    {#if has('orderedList')}<button type="button" role="menuitem" onclick={() => command('toggleOrderedList')}>{labels.orderedList}</button>{/if}
    {#if editor && (active.bulletList || active.orderedList)}<hr /><button type="button" role="menuitem" disabled={!editor.can().sinkListItem('listItem')} onclick={() => command('sinkListItem', 'listItem')}>{labels.indent}</button><button type="button" role="menuitem" disabled={!editor.can().liftListItem('listItem')} onclick={() => command('liftListItem', 'listItem')}>{labels.outdent}</button>{/if}
  </div>
  <div bind:this={moreMenu} id={`${id}-more`} popover="auto" class="tiptap-popover" role="menu" tabindex="-1" aria-label={labels.more} onkeydown={menuKeys}>
    {#each more as [key, mark, cmd]}<button type="button" role="menuitem" class:active={active[mark]} onclick={() => command(cmd)}>{labels[key]}</button>{/each}
    {#if has('horizontalRule')}<button type="button" role="menuitem" onclick={() => command('setHorizontalRule')}>{labels.horizontalRule}</button>{/if}
    {#if has('align')}{#each ['left', 'center', 'right'] as alignment}<button type="button" role="menuitem" onclick={() => command('setTextAlign', alignment)}>{labels[alignment]}</button>{/each}{/if}
    {#if has('color')}<label class="tiptap-color">{labels.color}<input type="color" aria-label={labels.color} value={colorHex(active.color)} oninput={event => editor.chain().setColor(event.currentTarget.value).run()} /></label><button type="button" role="menuitem" disabled={!active.color} onclick={() => command('unsetColor')}>{labels.resetColor}</button>{/if}
    {#if has('unsetMarks')}<hr /><button type="button" role="menuitem" onclick={() => { closeMenus(); removeTextFormatting(editor, parsedStyles) }}>{labels.clear}</button>{/if}
  </div>
  <div bind:this={anchorMenu} popover="auto" class="tiptap-popover tiptap-anchor-editor" role="dialog" tabindex="-1" aria-label={labels.anchor} onkeydown={menuKeys}>
    <label for={`${id}-anchor`}>{labels.anchorId}</label><input id={`${id}-anchor`} type="text" bind:value={anchorId} aria-invalid={!!anchorError} aria-describedby={`${id}-anchor-help`} />
    <p id={`${id}-anchor-help`}>{anchorError || labels.anchorHelp}</p>
    <div class="tiptap-popover-actions"><button type="button" class="primary" onclick={applyAnchor}>{labels.apply}</button><button type="button" onclick={() => command('unsetJumpAnchor')}>{labels.remove}</button><button type="button" onclick={async () => { await navigator.clipboard.writeText(`#${anchorId}`); notice = labels.copied }}>{labels.copyLink}</button></div>
  </div>
  <div bind:this={aiMenu} popover="auto" class="tiptap-popover tiptap-ai-editor" role="dialog" tabindex="-1" aria-label={labels.ai} onkeydown={menuKeys}>
    <label for={`${id}-ai-mode`}>{labels.ai}</label><select id={`${id}-ai-mode`} bind:value={aiMode}>{#each ['rewrite', 'shorten', 'continue'] as mode}<option value={mode}>{labels[mode]}</option>{/each}</select>
    <label for={`${id}-instruction`}>{labels.instruction}</label><input id={`${id}-instruction`} type="text" bind:value={instruction} />
    <button type="button" class="ai-action is-primary" onclick={generate}><Icon name="sparkles" />{labels.generate}</button>
  </div>
</div>
