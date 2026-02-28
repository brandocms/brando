import { minigl } from '@xdadda/mini-gl'

/**
 * Calculate crop region for a given ratio centered on the focal point.
 *
 * @param {number} focalX - Focal X in percentage (0-100)
 * @param {number} focalY - Focal Y in percentage (0-100)
 * @param {number} origWidth - Original image width in pixels
 * @param {number} origHeight - Original image height in pixels
 * @param {number} targetRatio - Target crop aspect ratio (width / height)
 * @param {number} zoom - Zoom level (1 = full, >1 = tighter crop)
 * @returns {{ left: number, top: number, width: number, height: number }}
 */
function calculateCropRegion(focalX, focalY, origWidth, origHeight, targetRatio, zoom) {
  let cropWidth, cropHeight

  if (targetRatio >= origWidth / origHeight) {
    cropWidth = origWidth
    cropHeight = Math.round(origWidth / targetRatio)
  } else {
    cropHeight = origHeight
    cropWidth = Math.round(origHeight * targetRatio)
  }

  // Apply zoom (shrink crop area)
  cropWidth = Math.round(cropWidth / zoom)
  cropHeight = Math.round(cropHeight / zoom)

  // Center on focal point (pixel coords)
  const focalPxX = (focalX / 100) * origWidth
  const focalPxY = (focalY / 100) * origHeight
  let anchorX = Math.round(focalPxX - cropWidth / 2)
  let anchorY = Math.round(focalPxY - cropHeight / 2)

  // Clamp to image bounds
  anchorX = Math.min(Math.max(0, anchorX), origWidth - cropWidth)
  anchorY = Math.min(Math.max(0, anchorY), origHeight - cropHeight)

  return { left: anchorX, top: anchorY, width: cropWidth, height: cropHeight }
}

/**
 * Draw crop region outlines on the overlay canvas.
 */
function drawCropOverlays(overlayCtx, cropRegions, displayScale, canvasOffsetX, canvasOffsetY) {
  const dpr = window.devicePixelRatio || 1
  overlayCtx.clearRect(0, 0, overlayCtx.canvas.width / dpr, overlayCtx.canvas.height / dpr)

  const colors = [
    'rgba(255, 100, 100, 0.8)',
    'rgba(100, 200, 255, 0.8)',
    'rgba(100, 255, 100, 0.8)',
    'rgba(255, 200, 100, 0.8)',
    'rgba(200, 100, 255, 0.8)'
  ]

  cropRegions.forEach((region, idx) => {
    const x = canvasOffsetX + region.left * displayScale
    const y = canvasOffsetY + region.top * displayScale
    const w = region.width * displayScale
    const h = region.height * displayScale

    overlayCtx.strokeStyle = colors[idx % colors.length]
    overlayCtx.lineWidth = 2
    overlayCtx.setLineDash([6, 4])
    overlayCtx.strokeRect(x, y, w, h)

    // Label
    overlayCtx.setLineDash([])
    overlayCtx.fillStyle = colors[idx % colors.length]
    overlayCtx.font = '11px monospace'
    overlayCtx.fillText(region.label, x + 4, y + 14)
  })
}

/**
 * Draw a single crop preview into a 2D canvas
 */
function drawCropPreview(previewCanvas, sourceImg, region) {
  const ctx = previewCanvas.getContext('2d')
  const dpr = window.devicePixelRatio || 1
  const previewWidth = 270
  const previewHeight = Math.round(previewWidth / (region.width / region.height))

  previewCanvas.width = Math.round(previewWidth * dpr)
  previewCanvas.height = Math.round(previewHeight * dpr)
  previewCanvas.style.width = previewWidth + 'px'
  previewCanvas.style.height = previewHeight + 'px'

  ctx.scale(dpr, dpr)
  ctx.drawImage(
    sourceImg,
    region.left, region.top, region.width, region.height,
    0, 0, previewWidth, previewHeight
  )
}

export default app => ({
  mounted() {
    this.glInstance = null
    this.sourceImg = null
    this.focalX = 50
    this.focalY = 50
    this.zoom = 1
    this.cropGroups = []
    this.imageWidth = 0
    this.imageHeight = 0
    this.isDragging = false
    this.freeformMode = false
    this.freeformRect = null
    this.freeformDragging = false
    this.freeformResizing = false

    this.handleEvent('b:image_editor:init', (payload) => {
      this.initEditor(payload)
    })
  },

  destroyed() {
    this.cleanup()
  },

  cleanup() {
    if (this.glInstance) {
      this.glInstance.destroy()
      this.glInstance = null
    }
    if (this._resizeObserver) {
      this._resizeObserver.disconnect()
      this._resizeObserver = null
    }
    this.sourceImg = null

    // Remove dynamically created preview canvases
    const previewsContainer = this.el.querySelector('#image-editor-previews')
    if (previewsContainer) {
      previewsContainer.innerHTML = ''
    }
  },

  initEditor(payload) {
    this.cleanup()

    this.imageWidth = payload.image_width
    this.imageHeight = payload.image_height
    this.focalX = payload.focal_x || 50
    this.focalY = payload.focal_y || 50
    this.cropGroups = payload.crop_groups || []
    this.zoom = 1
    this.freeformMode = this.cropGroups.length === 0

    // Reset zoom slider
    const zoomSlider = this.el.querySelector('#image-editor-zoom')
    if (zoomSlider) zoomSlider.value = '1'

    const zoomValue = this.el.querySelector('#image-editor-zoom-value')
    if (zoomValue) zoomValue.textContent = '1.00x'

    // Load the source image
    const img = new Image()
    img.crossOrigin = 'anonymous'
    img.onload = () => {
      this.sourceImg = img
      this.setupMainCanvas()
      this.setupPreviews()
      this.setupInteractions()
      this.updateAll()
      this.setupResizeObserver()
    }
    img.src = payload.image_src
  },

  setupResizeObserver() {
    const container = this.el.querySelector('.image-editor-main')
    if (!container) return

    if (this._resizeObserver) this._resizeObserver.disconnect()

    this._resizeObserver = new ResizeObserver(() => {
      if (!this.sourceImg) return
      this.setupMainCanvas()
      this.updateAll()
    })
    this._resizeObserver.observe(container)
  },

  setupMainCanvas() {
    const canvas = this.el.querySelector('#image-editor-canvas')
    const container = this.el.querySelector('.image-editor-main')

    if (!canvas || !container) return

    const dpr = window.devicePixelRatio || 1

    // Fit image into the container
    const containerRect = container.getBoundingClientRect()
    const maxW = containerRect.width - 20
    const maxH = containerRect.height - 20

    const imgRatio = this.imageWidth / this.imageHeight
    let displayW, displayH

    if (imgRatio >= maxW / maxH) {
      displayW = Math.min(maxW, this.imageWidth)
      displayH = displayW / imgRatio
    } else {
      displayH = Math.min(maxH, this.imageHeight)
      displayW = displayH * imgRatio
    }

    this.displayScale = displayW / this.imageWidth
    this.displayW = Math.round(displayW)
    this.displayH = Math.round(displayH)

    // Set canvas buffer size to account for device pixel ratio
    canvas.width = Math.round(displayW * dpr)
    canvas.height = Math.round(displayH * dpr)
    canvas.style.width = this.displayW + 'px'
    canvas.style.height = this.displayH + 'px'

    const ctx = canvas.getContext('2d')
    ctx.scale(dpr, dpr)
    ctx.drawImage(this.sourceImg, 0, 0, this.displayW, this.displayH)

    // Setup overlay canvas
    const overlay = this.el.querySelector('#image-editor-overlay')
    if (overlay) {
      overlay.width = Math.round(displayW * dpr)
      overlay.height = Math.round(displayH * dpr)
      overlay.style.width = this.displayW + 'px'
      overlay.style.height = this.displayH + 'px'

      // Position overlay on top of canvas
      overlay.style.position = 'absolute'
      overlay.style.left = canvas.offsetLeft + 'px'
      overlay.style.top = canvas.offsetTop + 'px'

      const overlayCtx = overlay.getContext('2d')
      overlayCtx.scale(dpr, dpr)
    }

    // Position focal pin
    this.updateFocalPin()
  },

  setupPreviews() {
    const previewsContainer = this.el.querySelector('#image-editor-previews')
    if (!previewsContainer) return

    previewsContainer.innerHTML = ''

    if (this.freeformMode) {
      // Freeform mode: show instructions and single preview
      const title = document.createElement('div')
      title.className = 'image-editor-previews-title'
      title.textContent = 'Freeform crop'
      previewsContainer.appendChild(title)

      const instructions = document.createElement('div')
      instructions.className = 'freeform-instructions'
      instructions.textContent = 'No crop ratios configured. Use focal point only.'
      previewsContainer.appendChild(instructions)
    } else {
      const title = document.createElement('div')
      title.className = 'image-editor-previews-title'
      title.textContent = 'Crop previews'
      previewsContainer.appendChild(title)

      // Create a preview canvas for each unique crop ratio
      this.previewCanvases = []
      this.cropGroups.forEach((group) => {
        const wrapper = document.createElement('div')
        wrapper.className = 'crop-preview'

        const previewCanvas = document.createElement('canvas')
        wrapper.appendChild(previewCanvas)

        const label = document.createElement('div')
        label.className = 'crop-preview-label'

        const labelText = document.createElement('span')
        labelText.textContent = group.label

        const sizes = document.createElement('span')
        sizes.className = 'crop-preview-sizes'
        sizes.textContent = group.size_keys.join(', ')

        label.appendChild(labelText)
        label.appendChild(sizes)
        wrapper.appendChild(label)

        previewsContainer.appendChild(wrapper)

        this.previewCanvases.push({
          canvas: previewCanvas,
          ratio: group.ratio,
          label: group.label,
          sizeKeys: group.size_keys
        })
      })
    }
  },

  setupInteractions() {
    const canvas = this.el.querySelector('#image-editor-canvas')
    if (!canvas) return

    // Remove old listeners
    if (this._onMouseDown) {
      canvas.removeEventListener('mousedown', this._onMouseDown)
      document.removeEventListener('mousemove', this._onMouseMove)
      document.removeEventListener('mouseup', this._onMouseUp)
      canvas.removeEventListener('touchstart', this._onTouchStart)
      document.removeEventListener('touchmove', this._onTouchMove)
      document.removeEventListener('touchend', this._onTouchEnd)
    }

    this._onMouseDown = (e) => {
      this.isDragging = true
      this.updateFocalFromEvent(e, canvas)
    }

    this._onMouseMove = (e) => {
      if (!this.isDragging) return
      this.updateFocalFromEvent(e, canvas)
    }

    this._onMouseUp = () => {
      this.isDragging = false
    }

    this._onTouchStart = (e) => {
      e.preventDefault()
      this.isDragging = true
      this.updateFocalFromEvent(e.touches[0], canvas)
    }

    this._onTouchMove = (e) => {
      if (!this.isDragging) return
      e.preventDefault()
      this.updateFocalFromEvent(e.touches[0], canvas)
    }

    this._onTouchEnd = () => {
      this.isDragging = false
    }

    canvas.addEventListener('mousedown', this._onMouseDown)
    document.addEventListener('mousemove', this._onMouseMove)
    document.addEventListener('mouseup', this._onMouseUp)
    canvas.addEventListener('touchstart', this._onTouchStart, { passive: false })
    document.addEventListener('touchmove', this._onTouchMove, { passive: false })
    document.addEventListener('touchend', this._onTouchEnd)

    // Zoom slider
    const zoomSlider = this.el.querySelector('#image-editor-zoom')
    if (zoomSlider) {
      if (this._onZoom) zoomSlider.removeEventListener('input', this._onZoom)
      this._onZoom = (e) => {
        this.zoom = parseFloat(e.target.value)
        const zoomValue = this.el.querySelector('#image-editor-zoom-value')
        if (zoomValue) zoomValue.textContent = this.zoom.toFixed(2) + 'x'
        this.updateAll()
      }
      zoomSlider.addEventListener('input', this._onZoom)
    }

    // Reset button
    const resetBtn = this.el.querySelector('#image-editor-reset')
    if (resetBtn) {
      if (this._onReset) resetBtn.removeEventListener('click', this._onReset)
      this._onReset = () => {
        this.focalX = 50
        this.focalY = 50
        this.zoom = 1
        const slider = this.el.querySelector('#image-editor-zoom')
        if (slider) slider.value = '1'
        const zoomValue = this.el.querySelector('#image-editor-zoom-value')
        if (zoomValue) zoomValue.textContent = '1.00x'
        this.updateAll()
      }
      resetBtn.addEventListener('click', this._onReset)
    }

    // Save replace button
    const saveReplaceBtn = this.el.querySelector('#image-editor-save-replace')
    if (saveReplaceBtn) {
      if (this._onSaveReplace) saveReplaceBtn.removeEventListener('click', this._onSaveReplace)
      this._onSaveReplace = () => {
        this.pushEventTo(this.el, 'image_editor_save', {
          mode: 'replace',
          focal_x: Math.round(this.focalX),
          focal_y: Math.round(this.focalY)
        })
        this.closeDrawer()
      }
      saveReplaceBtn.addEventListener('click', this._onSaveReplace)
    }

    // Save as new copy button
    const saveNewBtn = this.el.querySelector('#image-editor-save-new')
    if (saveNewBtn) {
      if (this._onSaveNew) saveNewBtn.removeEventListener('click', this._onSaveNew)
      this._onSaveNew = () => {
        this.saveAsNewCopy()
        this.closeDrawer()
      }
      saveNewBtn.addEventListener('click', this._onSaveNew)
    }
  },

  updateFocalFromEvent(e, canvas) {
    const rect = canvas.getBoundingClientRect()
    const x = Math.max(0, Math.min(100, ((e.clientX - rect.left) / rect.width) * 100))
    const y = Math.max(0, Math.min(100, ((e.clientY - rect.top) / rect.height) * 100))
    this.focalX = x
    this.focalY = y
    this.updateAll()
  },

  updateAll() {
    this.updateFocalPin()
    this.updateCropOverlays()
    this.updateCropPreviews()
  },

  updateFocalPin() {
    const pin = this.el.querySelector('.image-editor-focal-pin')
    const canvas = this.el.querySelector('#image-editor-canvas')
    if (!pin || !canvas) return

    pin.style.left = canvas.offsetLeft + (this.focalX / 100) * this.displayW + 'px'
    pin.style.top = canvas.offsetTop + (this.focalY / 100) * this.displayH + 'px'
    pin.classList.add('visible')
  },

  updateCropOverlays() {
    const overlay = this.el.querySelector('#image-editor-overlay')
    if (!overlay || !this.sourceImg) return

    const ctx = overlay.getContext('2d')
    if (!ctx) return

    const regions = this.cropGroups.map((group) => {
      const region = calculateCropRegion(
        this.focalX, this.focalY,
        this.imageWidth, this.imageHeight,
        group.ratio, this.zoom
      )
      return { ...region, label: group.label }
    })

    drawCropOverlays(ctx, regions, this.displayScale, 0, 0)
  },

  updateCropPreviews() {
    if (!this.previewCanvases || !this.sourceImg) return

    this.previewCanvases.forEach((preview) => {
      const region = calculateCropRegion(
        this.focalX, this.focalY,
        this.imageWidth, this.imageHeight,
        preview.ratio, this.zoom
      )
      drawCropPreview(preview.canvas, this.sourceImg, region)
    })
  },

  closeDrawer() {
    const closeBtn = document.querySelector('#image-editor-drawer .drawer-close-button')
    if (closeBtn) closeBtn.click()
  },

  saveAsNewCopy() {
    // Use the main canvas or create a temporary one for export
    const exportCanvas = document.createElement('canvas')
    const ctx = exportCanvas.getContext('2d')

    if (this.cropGroups.length > 0) {
      // Export at original resolution using the first crop ratio
      const region = calculateCropRegion(
        this.focalX, this.focalY,
        this.imageWidth, this.imageHeight,
        this.cropGroups[0].ratio, this.zoom
      )
      exportCanvas.width = region.width
      exportCanvas.height = region.height
      ctx.drawImage(
        this.sourceImg,
        region.left, region.top, region.width, region.height,
        0, 0, region.width, region.height
      )
    } else {
      // Freeform — export full image
      exportCanvas.width = this.imageWidth
      exportCanvas.height = this.imageHeight
      ctx.drawImage(this.sourceImg, 0, 0)
    }

    exportCanvas.toBlob((blob) => {
      if (!blob) return

      // Use the live_file_input upload mechanism
      const uploadInput = document.querySelector('#image-drawer-form input[type="file"]')
      if (uploadInput) {
        const file = new File([blob], 'cropped-image.jpg', { type: 'image/jpeg' })
        const dataTransfer = new DataTransfer()
        dataTransfer.items.add(file)
        uploadInput.files = dataTransfer.files
        uploadInput.dispatchEvent(new Event('change', { bubbles: true }))

        // Push the new focal point to save on the uploaded image
        this.pushEventTo(this.el, 'image_editor_save', {
          mode: 'new_copy',
          focal_x: Math.round(this.focalX),
          focal_y: Math.round(this.focalY)
        })
      }
    }, 'image/jpeg', 0.95)
  }
})
