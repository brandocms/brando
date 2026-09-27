// A visual study of the shared identifier. This page never contacts the CMS.
const entries = [
  { id: 1, title: 'Havglimt retreat', type: 'Case', language: 'EN', status: 'Published', cover: '../content-agent-concepts/media/architecture.jpg' },
  { id: 2, title: 'The garden rooms', type: 'Case', language: 'EN', status: 'Published', cover: '../content-agent-concepts/media/room.jpg' },
  { id: 3, title: 'A quieter corner of the coast', type: 'Page', language: 'NO', status: 'Draft' },
]
const variants = [
  { id: 'a', title: 'Compact cards', description: 'A clear boundary around every item. Quiet, compact and easy to reorder.' },
  { id: 'b', title: 'Joined list', description: 'One outline with divided rows. A denser list with less repeated framing.' },
  { id: 'c', title: 'Cover rows', description: 'The entry’s cover leads. A document icon fills in when no cover is set.' },
  { id: 'd', title: 'Joined cover rows', description: 'One shared outline, thin dividers and a cover for each entry. Actions sit in the footer.' },
]
let selected = [1, 2]
const icon = name => `<span class="hero-${name}" aria-hidden="true"></span>`
const grip = '<span class="grip" aria-hidden="true">' + '<i></i>'.repeat(6) + '</span>'
const escape = text => text.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('"', '&quot;')
const entryMarkup = (entry, picker = false) => {
  const active = selected.includes(entry.id)
  const content = `${picker ? '' : grip}<span class="cover">${entry.cover ? `<img src="${entry.cover}" alt="">` : icon('document-text')}</span>
    <span class="identifier-copy"><span class="identifier-title">${escape(entry.title)}</span><span class="identifier-meta">
      <span>${entry.type}</span><span class="separator">·</span><span>${entry.language}</span><span class="separator">·</span>
      <span class="identifier-status"><i class="dot ${entry.status === 'Draft' ? 'draft' : ''}"></i>${entry.status}</span>
    </span></span>`
  return picker
    ? `<button class="identifier ${active ? 'selected' : ''}" aria-pressed="${active}" data-toggle="${entry.id}">${content}<span class="selection">${active ? icon('check') : ''}</span></button>`
    : `<div class="identifier" draggable="true" data-entry="${entry.id}">${content}<button class="row-action" data-remove="${entry.id}" aria-label="Remove ${escape(entry.title)}">${icon('x-mark')}</button></div>`
}
function render() {
  for (const variant of document.querySelectorAll('.variant')) {
    const list = variant.querySelector('.entry-field .identifier-list')
    list.innerHTML = selected.length ? selected.map(id => entryMarkup(entries.find(e => e.id === id))).join('') : '<div class="empty">No selected entries</div>'
    variant.querySelector('.count').textContent = `${selected.length} selected`
    variant.querySelector('[data-clear]').disabled = !selected.length
    const query = variant.querySelector('input').value.toLowerCase()
    const matches = entries.filter(e => e.title.toLowerCase().includes(query))
    variant.querySelector('.picker .identifier-list').innerHTML = matches.map(entry => entryMarkup(entry, true)).join('') || '<div class="empty">No matching entries</div>'
  }
}
document.querySelector('#comparison').innerHTML = variants.map(v => `
  <section class="variant variant-${v.id}" id="variant-${v.id}">
    <header class="variant-heading"><h2><span class="letter">${v.id.toUpperCase()}</span>${v.title}${v.id === 'd' ? '<span class="recommend">New</span>' : ''}</h2><p>${v.description}</p></header>
    <div class="example-label">In a form · selected items</div>
    <div class="surface"><div class="field-label">Related entries <span class="count"></span></div>
      <div class="entry-field"><div class="field-icon">${icon('link')}</div><div class="identifier-list"></div>
        <div class="field-actions"><button data-open>Select entries</button><button data-clear>Clear all</button></div>
      </div><p class="hint">Select up to 3 entries. Drag items to reorder.</p>
    </div>
    <div class="example-label">In a picker · selected and available items</div>
    <div class="surface picker"><div class="field-label">Select entries <span class="count-label">3 available</span></div>
      <label class="search">${icon('magnifying-glass')}<input type="search" placeholder="Filter entries…" aria-label="Filter entries in variant ${v.id.toUpperCase()}"></label>
      <div class="identifier-list"></div>
    </div>
  </section>`).join('')
render()
document.addEventListener('click', event => {
  const button = event.target.closest('button')
  if (!button) return
  if (button.dataset.view) {
    document.querySelector('#comparison').dataset.view = button.dataset.view
    document.querySelectorAll('.variant').forEach(v => { v.hidden = button.dataset.view !== 'all' && v.id !== `variant-${button.dataset.view}` })
    document.querySelectorAll('button[data-view]').forEach(b => b.setAttribute('aria-pressed', b === button))
    return
  }
  if (button.hasAttribute('data-open')) {
    button.closest('.variant').querySelector('input').focus()
    return
  }
  const id = Number(button.dataset.remove || button.dataset.toggle)
  if (button.id === 'reset') selected = [1, 2]
  else if (button.hasAttribute('data-clear')) selected = []
  else if (button.dataset.remove || selected.includes(id)) selected = selected.filter(value => value !== id)
  else if (button.dataset.toggle) selected.push(id)
  render()
  document.querySelector('#status').textContent = `${selected.length} entries selected in the preview.`
})
document.addEventListener('input', event => { if (event.target.matches('input[type=search]')) render() })
let dragged
document.addEventListener('dragstart', event => { dragged = Number(event.target.closest('[data-entry]')?.dataset.entry); event.dataTransfer.effectAllowed = 'move' })
document.addEventListener('dragover', event => { if (event.target.closest('[data-entry]')) event.preventDefault() })
document.addEventListener('drop', event => {
  const target = Number(event.target.closest('[data-entry]')?.dataset.entry)
  if (!target || !dragged || target === dragged) return
  event.preventDefault()
  const from = selected.indexOf(dragged), to = selected.indexOf(target)
  selected.splice(from, 1)
  selected.splice(to, 0, dragged)
  render()
})
const initialView = location.hash.slice(1)
if (variants.some(variant => variant.id === initialView)) document.querySelector(`button[data-view="${initialView}"]`).click()
