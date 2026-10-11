// Tab contents are already mounted. Keep this navigation local, using sticky
// classes so validation and collaboration patches cannot move the editor back.
// A failed save explicitly selects the tab with the error.
export default function formTabs(hook) {
  let selected = hook.el.querySelector('[data-form-tab].active')?.dataset.formTab

  const apply = () => {
    if (!selected) return
    const js = hook.js()
    hook.el.querySelectorAll('[data-form-tab], [data-form-tab-panel]').forEach(el => {
      const active = (el.dataset.formTab ?? el.dataset.tabName) === selected
      if (active) js.addClass(el, 'active')
      else js.removeClass(el, 'active')
      if (el.hasAttribute('data-form-tab')) js.setAttribute(el, 'aria-pressed', String(active))
      // Attributes apply synchronously; the error-scroll event in the same
      // reply must see the newly visible panel before the class command's RAF.
      else js.setAttribute(el, 'data-tab-active', String(active))
    })
  }

  const select = name => {
    if (!hook.el.querySelector(`[data-form-tab="${CSS.escape(name)}"]`)) return
    selected = name
    apply()
  }

  const onSelect = event => select(event.target.dataset.formTab)
  hook.el.addEventListener('b:form-tab', onSelect)
  const serverEvent = hook.handleEvent('b:select_form_tab', ({ id, name }) => {
    if (id === hook.el.id && name) select(name)
  })

  return {
    updated: apply,
    destroy() {
      hook.el.removeEventListener('b:form-tab', onSelect)
      hook.removeHandleEvent(serverEvent)
    },
  }
}
