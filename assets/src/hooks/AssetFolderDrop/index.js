export default app => ({
  mounted() {
    this.dropEvent = this.el.dataset.dropEvent || 'assets_move_selected_to_folder'
    this.dropFolder = this.el.dataset.dropFolder || ''
    this.dropTarget = this.el.dataset.dropTarget || null

    console.log('[AssetFolderDrop] mounted', {
      folder: this.dropFolder,
      target: this.dropTarget,
      event: this.dropEvent,
    })

    this.handleDragEnter = this.handleDragEnter.bind(this)
    this.handleDragOver = this.handleDragOver.bind(this)
    this.handleDragLeave = this.handleDragLeave.bind(this)
    this.handleDrop = this.handleDrop.bind(this)

    this.el.addEventListener('dragenter', this.handleDragEnter, false)
    this.el.addEventListener('dragover', this.handleDragOver, false)
    this.el.addEventListener('dragleave', this.handleDragLeave, false)
    this.el.addEventListener('drop', this.handleDrop, false)
  },

  destroyed() {
    this.el.removeEventListener('dragenter', this.handleDragEnter, false)
    this.el.removeEventListener('dragover', this.handleDragOver, false)
    this.el.removeEventListener('dragleave', this.handleDragLeave, false)
    this.el.removeEventListener('drop', this.handleDrop, false)
    this.el.classList.remove('drop-active')
  },

  handleDragEnter(e) {
    if (!this.isSelectionDrag(e)) return
    e.preventDefault()
    console.log('[AssetFolderDrop] dragenter', this.dropFolder)
    this.el.classList.add('drop-active')
  },

  handleDragOver(e) {
    if (!this.isSelectionDrag(e)) return
    e.preventDefault()
    if (e.dataTransfer) e.dataTransfer.dropEffect = 'move'
    console.log('[AssetFolderDrop] dragover', this.dropFolder)
    this.el.classList.add('drop-active')
  },

  handleDragLeave(e) {
    if (!this.isSelectionDrag(e)) return
    e.preventDefault()
    console.log('[AssetFolderDrop] dragleave', this.dropFolder)
    this.el.classList.remove('drop-active')
  },

  handleDrop(e) {
    if (!this.isSelectionDrag(e)) return
    e.preventDefault()
    this.el.classList.remove('drop-active')

    const ids = this.getDraggedSelectedIds(e)
    if (!Array.isArray(ids) || ids.length === 0) {
      console.log('[AssetFolderDrop] drop ignored, no ids')
      return
    }
    console.log('[AssetFolderDrop] drop', { folder: this.dropFolder, ids })

    const eventPayload = {
      folder: this.dropFolder,
      ids: ids,
    }

    if (this.dropTarget) {
      console.log('[AssetFolderDrop] pushEventTo', this.dropTarget, this.dropEvent)
      this.pushEventTo(this.dropTarget, this.dropEvent, eventPayload)
    } else {
      console.log('[AssetFolderDrop] pushEvent', this.dropEvent)
      this.pushEvent(this.dropEvent, eventPayload)
    }
  },

  getDraggedSelectedIds(e) {
    const transferIds = this.getDataTransferSelectedIds(e)
    if (transferIds.length > 0) return transferIds

    const globalIds = window.__brandoSelectedIdsDrag
    if (!Array.isArray(globalIds)) return []
    return globalIds.map(Number).filter(Number.isFinite)
  },

  getDataTransferSelectedIds(e) {
    const payload = e.dataTransfer?.getData('application/x-brando-selected-ids')
    if (!payload) return []

    try {
      const ids = JSON.parse(payload)
      if (!Array.isArray(ids)) return []
      return ids.map(Number).filter(Number.isFinite)
    } catch (_err) {
      return []
    }
  },

  isSelectionDrag(e) {
    const globalIds = window.__brandoSelectedIdsDrag
    if (Array.isArray(globalIds) && globalIds.length > 0) return true

    const types = e.dataTransfer?.types || []
    return Array.from(types).includes('application/x-brando-selected-ids')
  },
})
