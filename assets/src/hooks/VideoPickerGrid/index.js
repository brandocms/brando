export default app => ({
  mounted() {
    this.targetComponent = this.el.dataset.targetComponent || null

    // Intercept shift+clicks on video rows BEFORE LiveView's click handler.
    // LiveView binds on `document` with capture, so we bind on `window` with
    // capture to fire first (window is outer to document in capture phase).
    this._clickHandler = (ev) => {
      if (!ev.shiftKey) return

      const row = ev.target.closest('.video-picker__video[data-id]')
      if (!row || !this.el.contains(row)) return

      ev.stopImmediatePropagation()
      ev.preventDefault()

      const id = row.dataset.id
      const payload = {
        id: id,
        shift: true,
        meta: ev.metaKey || ev.ctrlKey
      }

      if (this.targetComponent) {
        this.pushEventTo(this.targetComponent, 'organize_select_video', payload)
      } else {
        this.pushEvent('organize_select_video', payload)
      }
    }

    // Drag start for organize-selected videos
    this._dragStartHandler = (ev) => {
      const row = ev.target.closest('.video-picker__video[data-id]')
      if (!row || !this.el.contains(row) || !ev.dataTransfer) return

      const selectedIds = Array.from(
        this.el.querySelectorAll('.video-picker__video.organize-selected[data-id]')
      )
        .map(el => Number(el.dataset.id))
        .filter(Number.isFinite)

      if (selectedIds.length === 0) return

      ev.dataTransfer.effectAllowed = 'move'
      ev.dataTransfer.setData(
        'application/x-brando-selected-ids',
        JSON.stringify(selectedIds)
      )
      ev.dataTransfer.setData('text/plain', `${selectedIds.length}`)
      window.__brandoSelectedIdsDrag = selectedIds

      // Custom drag image showing count
      const ghost = document.createElement('div')
      ghost.className = 'video-picker-drag-ghost'
      ghost.textContent = `${selectedIds.length}`
      document.body.appendChild(ghost)
      ev.dataTransfer.setDragImage(ghost, 20, 20)
      this._dragGhost = ghost

      this.el.classList.add('selection-dragging')
      document.body.classList.add('selection-dragging')
    }

    this._dragEndHandler = () => {
      if (this._dragGhost) {
        this._dragGhost.remove()
        this._dragGhost = null
      }
      this.el.classList.remove('selection-dragging')
      document.body.classList.remove('selection-dragging')
      window.__brandoSelectedIdsDrag = null
    }

    // Use window-level capture to beat LiveView's document-level capture listener
    window.addEventListener('click', this._clickHandler, true)
    this.el.addEventListener('dragstart', this._dragStartHandler, true)
    this.el.addEventListener('dragend', this._dragEndHandler, false)

    // Server pushes unified selection state
    this.handleEvent('video_picker_selection_changed', ({ selected_ids, organize_ids }) => {
      const selectedSet = new Set(selected_ids.map(String))
      const organizeSet = new Set(organize_ids.map(String))

      this.el.querySelectorAll('.video-picker__video[data-id]').forEach(el => {
        const id = el.dataset.id
        el.classList.toggle('selected', selectedSet.has(id))
        el.classList.toggle('organize-selected', organizeSet.has(id))
        el.draggable = organizeSet.has(id)
      })

      this.el.classList.toggle('video-picker-grid--organizing', organizeSet.size > 0)
    })
  },

  destroyed() {
    window.removeEventListener('click', this._clickHandler, true)
    this.el.removeEventListener('dragstart', this._dragStartHandler, true)
    this.el.removeEventListener('dragend', this._dragEndHandler, false)
    document.body.classList.remove('selection-dragging')
    window.__brandoSelectedIdsDrag = null
  }
})
