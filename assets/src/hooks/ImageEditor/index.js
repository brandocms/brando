import { minigl } from '@xdadda/mini-gl'

/**
 * Preset ratios for freeform crop mode.
 * key: display label, w/h: ratio components (0/0 = unconstrained free crop)
 */
const FREEFORM_RATIOS = [
  { key: 'free', label: 'Free', w: 0, h: 0 },
  { key: '1:1', label: '1:1', w: 1, h: 1 },
  { key: '2:3', label: '2:3', w: 2, h: 3 },
  { key: '3:2', label: '3:2', w: 3, h: 2 },
  { key: '4:5', label: '4:5', w: 4, h: 5 },
  { key: '5:4', label: '5:4', w: 5, h: 4 },
  { key: '16:10', label: '16:10', w: 16, h: 10 }
]

/**
 * Generate an SVG rectangle icon for a ratio button.
 */
function ratioSVG(w, h, isFree) {
  const vs = 28
  const maxS = 20
  const pad = (vs - maxS) / 2

  if (isFree) {
    return `<svg viewBox="0 0 ${vs} ${vs}" width="${vs}" height="${vs}">
      <rect x="${pad}" y="${pad}" width="${maxS}" height="${maxS}" rx="1.5"
            fill="none" stroke="currentColor" stroke-width="1.5" stroke-dasharray="3 2"/>
    </svg>`
  }

  const ratio = w / h
  let rw, rh
  if (ratio >= 1) {
    rw = maxS
    rh = maxS / ratio
  } else {
    rh = maxS
    rw = maxS * ratio
  }

  const rx = (vs - rw) / 2
  const ry = (vs - rh) / 2

  return `<svg viewBox="0 0 ${vs} ${vs}" width="${vs}" height="${vs}">
    <rect x="${rx.toFixed(1)}" y="${ry.toFixed(1)}" width="${rw.toFixed(1)}" height="${rh.toFixed(1)}" rx="1.5"
          fill="none" stroke="currentColor" stroke-width="1.5"/>
  </svg>`
}

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
 * Draw configured-ratio crop frame overlay.
 * Primary (first) region: dimmed exterior, solid white border, rule-of-thirds, L-handles.
 * Secondary regions: colored dashed outlines with labels.
 */
function drawConfiguredOverlays(overlayCtx, cropRegions, displayScale) {
  const dpr = window.devicePixelRatio || 1
  const cw = overlayCtx.canvas.width / dpr
  const ch = overlayCtx.canvas.height / dpr
  overlayCtx.clearRect(0, 0, cw, ch)

  if (cropRegions.length === 0) return

  const primary = cropRegions[0]
  const px = primary.left * displayScale
  const py = primary.top * displayScale
  const pw = primary.width * displayScale
  const ph = primary.height * displayScale

  // Dim outside primary crop
  overlayCtx.fillStyle = 'rgba(0, 0, 0, 0.5)'
  overlayCtx.fillRect(0, 0, cw, ch)
  overlayCtx.clearRect(px, py, pw, ph)

  // Primary border
  overlayCtx.strokeStyle = 'rgba(255, 255, 255, 0.9)'
  overlayCtx.lineWidth = 1.5
  overlayCtx.setLineDash([])
  overlayCtx.strokeRect(px, py, pw, ph)

  // Rule-of-thirds grid
  overlayCtx.strokeStyle = 'rgba(255, 255, 255, 0.15)'
  overlayCtx.lineWidth = 0.5
  for (let i = 1; i <= 2; i++) {
    overlayCtx.beginPath()
    overlayCtx.moveTo(px + (pw * i) / 3, py)
    overlayCtx.lineTo(px + (pw * i) / 3, py + ph)
    overlayCtx.stroke()
    overlayCtx.beginPath()
    overlayCtx.moveTo(px, py + (ph * i) / 3)
    overlayCtx.lineTo(px + pw, py + (ph * i) / 3)
    overlayCtx.stroke()
  }

  // L-corner handles
  const cl = Math.min(16, Math.min(pw, ph) * 0.2)
  overlayCtx.strokeStyle = 'white'
  overlayCtx.lineWidth = 2.5
  overlayCtx.lineCap = 'square'
  // NW
  overlayCtx.beginPath()
  overlayCtx.moveTo(px, py + cl)
  overlayCtx.lineTo(px, py)
  overlayCtx.lineTo(px + cl, py)
  overlayCtx.stroke()
  // NE
  overlayCtx.beginPath()
  overlayCtx.moveTo(px + pw - cl, py)
  overlayCtx.lineTo(px + pw, py)
  overlayCtx.lineTo(px + pw, py + cl)
  overlayCtx.stroke()
  // SW
  overlayCtx.beginPath()
  overlayCtx.moveTo(px, py + ph - cl)
  overlayCtx.lineTo(px, py + ph)
  overlayCtx.lineTo(px + cl, py + ph)
  overlayCtx.stroke()
  // SE
  overlayCtx.beginPath()
  overlayCtx.moveTo(px + pw - cl, py + ph)
  overlayCtx.lineTo(px + pw, py + ph)
  overlayCtx.lineTo(px + pw, py + ph - cl)
  overlayCtx.stroke()

  // Secondary regions — colored dashed outlines
  const colors = [
    'rgba(100, 200, 255, 0.8)',
    'rgba(100, 255, 100, 0.8)',
    'rgba(255, 200, 100, 0.8)',
    'rgba(200, 100, 255, 0.8)'
  ]
  cropRegions.slice(1).forEach((region, idx) => {
    const x = region.left * displayScale
    const y = region.top * displayScale
    const w = region.width * displayScale
    const h = region.height * displayScale
    const color = colors[idx % colors.length]
    overlayCtx.strokeStyle = color
    overlayCtx.lineWidth = 1.5
    overlayCtx.setLineDash([6, 4])
    overlayCtx.strokeRect(x, y, w, h)
    overlayCtx.setLineDash([])
    overlayCtx.fillStyle = color
    overlayCtx.font = '11px monospace'
    overlayCtx.fillText(region.label, x + 4, y + 14)
  })
}

/**
 * Draw a single crop preview into a 2D canvas
 */
function drawCropPreview(previewCanvas, sourceImg, region) {
  const dpr = window.devicePixelRatio || 1
  const displayWidth = previewCanvas.parentElement?.clientWidth || 270
  const aspectRatio = region.width / region.height
  const displayHeight = Math.round(displayWidth / aspectRatio)

  // Set buffer size; remove inline styles so CSS width:100% + height:auto handles display
  const bufW = Math.round(displayWidth * dpr)
  const bufH = Math.round(displayHeight * dpr)
  previewCanvas.width = bufW
  previewCanvas.height = bufH
  previewCanvas.style.removeProperty('width')
  previewCanvas.style.removeProperty('height')

  const ctx = previewCanvas.getContext('2d')
  ctx.drawImage(
    sourceImg,
    region.left, region.top, region.width, region.height,
    0, 0, bufW, bufH
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

    // Freeform crop state
    this.cropRect = null            // { left, top, width, height } in original image coords
    this.freeformSelectedRatio = null // null = free, or w/h number
    this.freeformDragState = null    // { mode, startX, startY, startRect, anchor }
    this.freeformFocalDrag = false   // true when dragging focal point outside crop rect
    this.freeformPreviewCanvas = null

    // Configured ratio crop frame drag state
    this.cropFrameDragState = null  // { mode, startX, startY, startFocalX, startFocalY, startZoom, cornerOffset }

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
    this.cropRect = null
    this.freeformDragState = null
    this.freeformFocalDrag = false
    this.freeformPreviewCanvas = null
    this.cropFrameDragState = null

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
    this.fromBlock = !!payload.from_block
    this.imageId = payload.image_id || null
    this.configTarget = payload.config_target || null

    // Freeform state
    this.freeformSelectedRatio = null
    this.cropRect = null
    this.freeformDragState = null

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

      // Use actual loaded dimensions — the server-provided values may be stale
      // (e.g. after a crop that updated the DB but the :original file differs).
      this.imageWidth = img.naturalWidth
      this.imageHeight = img.naturalHeight

      // Initialize freeform crop rect after image loads
      if (this.freeformMode) {
        this.initCropRect()
      }

      this.setupMainCanvas()
      this.setupPreviews()
      this.setupInteractions()
      this.updateAll()
      this.setupResizeObserver()
    }
    img.src = payload.image_src
  },

  /**
   * Initialize the crop rectangle for freeform mode.
   * Centers the crop and makes it as large as possible for the selected ratio.
   */
  initCropRect(ratio) {
    const r = ratio !== undefined ? ratio : this.freeformSelectedRatio
    const iw = this.imageWidth
    const ih = this.imageHeight

    if (r === null) {
      // Free mode: cover 80% of the image, centered
      const w = Math.round(iw * 0.8)
      const h = Math.round(ih * 0.8)
      this.cropRect = {
        left: Math.round((iw - w) / 2),
        top: Math.round((ih - h) / 2),
        width: w,
        height: h
      }
    } else {
      // Ratio mode: largest rectangle at this ratio that fits the image
      let w, h
      if (r >= iw / ih) {
        w = iw
        h = Math.round(iw / r)
      } else {
        h = ih
        w = Math.round(ih * r)
      }
      this.cropRect = {
        left: Math.round((iw - w) / 2),
        top: Math.round((ih - h) / 2),
        width: w,
        height: h
      }
    }
  },

  /**
   * Handle ratio button click in freeform mode.
   */
  selectFreeformRatio(key) {
    const entry = FREEFORM_RATIOS.find(r => r.key === key)
    if (!entry) return

    const newRatio = entry.w === 0 ? null : entry.w / entry.h
    this.freeformSelectedRatio = newRatio

    // Adjust crop rect to the new ratio, keeping center if possible
    if (this.cropRect) {
      const cx = this.cropRect.left + this.cropRect.width / 2
      const cy = this.cropRect.top + this.cropRect.height / 2

      if (newRatio === null) {
        // Switching to free: keep current rect
      } else {
        // Calculate new dimensions at this ratio, using current size as guide
        const currentArea = this.cropRect.width * this.cropRect.height
        let w = Math.sqrt(currentArea * newRatio)
        let h = w / newRatio

        // Clamp to image bounds
        if (w > this.imageWidth) { w = this.imageWidth; h = w / newRatio }
        if (h > this.imageHeight) { h = this.imageHeight; w = h * newRatio }

        w = Math.round(w)
        h = Math.round(h)

        let left = Math.round(cx - w / 2)
        let top = Math.round(cy - h / 2)
        left = Math.max(0, Math.min(left, this.imageWidth - w))
        top = Math.max(0, Math.min(top, this.imageHeight - h))

        this.cropRect = { left, top, width: w, height: h }
      }
    } else {
      this.initCropRect(newRatio)
    }

    // Reset zoom to match the new crop size
    this.syncZoomFromCropRect()

    // Update active button state
    this.el.querySelectorAll('.ratio-btn').forEach(btn => {
      btn.classList.toggle('active', btn.dataset.ratio === key)
    })

    this.updateAll()
  },

  /**
   * Sync the zoom slider to reflect the current crop rect size.
   */
  syncZoomFromCropRect() {
    if (!this.cropRect) return

    const r = this.freeformSelectedRatio || (this.cropRect.width / this.cropRect.height)
    let maxW, maxH
    if (r >= this.imageWidth / this.imageHeight) {
      maxW = this.imageWidth
      maxH = this.imageWidth / r
    } else {
      maxH = this.imageHeight
      maxW = this.imageHeight * r
    }

    this.zoom = Math.max(1, maxW / this.cropRect.width)

    const slider = this.el.querySelector('#image-editor-zoom')
    if (slider) slider.value = String(Math.min(3, this.zoom))

    const zoomValue = this.el.querySelector('#image-editor-zoom-value')
    if (zoomValue) zoomValue.textContent = Math.min(3, this.zoom).toFixed(2) + 'x'
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
      // Ratio buttons bar
      const ratiosBar = document.createElement('div')
      ratiosBar.className = 'freeform-ratios'

      FREEFORM_RATIOS.forEach(entry => {
        const btn = document.createElement('button')
        btn.type = 'button'
        btn.className = 'ratio-btn'
        btn.dataset.ratio = entry.key
        if ((entry.w === 0 && this.freeformSelectedRatio === null) ||
            (entry.w !== 0 && this.freeformSelectedRatio === entry.w / entry.h)) {
          btn.classList.add('active')
        }

        btn.innerHTML = ratioSVG(entry.w, entry.h, entry.w === 0)
        const label = document.createElement('span')
        label.className = 'ratio-btn-label'
        label.textContent = entry.label
        btn.appendChild(label)

        btn.addEventListener('click', () => this.selectFreeformRatio(entry.key))
        ratiosBar.appendChild(btn)
      })

      previewsContainer.appendChild(ratiosBar)

      // Single preview canvas
      const previewWrapper = document.createElement('div')
      previewWrapper.className = 'freeform-preview'

      const previewCanvas = document.createElement('canvas')
      previewWrapper.appendChild(previewCanvas)
      previewsContainer.appendChild(previewWrapper)

      this.freeformPreviewCanvas = previewCanvas
    } else {
      const title = document.createElement('div')
      title.className = 'image-editor-previews-title'
      title.textContent = this.el.dataset.labelCropPreviews || 'Crop previews'
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

    if (this.freeformMode) {
      // Freeform mode: interact with crop rectangle
      this._onMouseDown = (e) => this.freeformMouseDown(e, canvas)
      this._onMouseMove = (e) => this.freeformMouseMove(e, canvas)
      this._onMouseUp = () => this.freeformMouseUp()

      this._onTouchStart = (e) => {
        e.preventDefault()
        this.freeformMouseDown(e.touches[0], canvas)
      }
      this._onTouchMove = (e) => {
        if (!this.freeformDragState && !this.freeformFocalDrag) return
        e.preventDefault()
        this.freeformMouseMove(e.touches[0], canvas)
      }
      this._onTouchEnd = () => this.freeformMouseUp()
    } else {
      // Configured ratio mode: interact with crop frame (drag to move, corner-drag to resize)
      this._onMouseDown = (e) => this.cropFrameMouseDown(e, canvas)
      this._onMouseMove = (e) => this.cropFrameMouseMove(e, canvas)
      this._onMouseUp = () => this.cropFrameMouseUp()

      this._onTouchStart = (e) => {
        e.preventDefault()
        this.cropFrameMouseDown(e.touches[0], canvas)
      }
      this._onTouchMove = (e) => {
        if (!this.cropFrameDragState) return
        e.preventDefault()
        this.cropFrameMouseMove(e.touches[0], canvas)
      }
      this._onTouchEnd = () => this.cropFrameMouseUp()
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

        if (this.freeformMode && this.cropRect) {
          this.resizeCropRectFromZoom()
        }

        this.updateAll()
      }
      zoomSlider.addEventListener('input', this._onZoom)
    }

    // Reset button
    const resetBtn = this.el.querySelector('#image-editor-reset')
    if (resetBtn) {
      if (this._onReset) resetBtn.removeEventListener('click', this._onReset)
      this._onReset = () => {
        if (this.freeformMode) {
          this.freeformSelectedRatio = null
          this.initCropRect()
          this.el.querySelectorAll('.ratio-btn').forEach(btn => {
            btn.classList.toggle('active', btn.dataset.ratio === 'free')
          })
          this.syncZoomFromCropRect()
        } else {
          this.focalX = 50
          this.focalY = 50
        }
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
        const hasCrop = (this.freeformMode && this.cropRect) || (!this.freeformMode && this.zoom > 1)

        if (hasCrop && this.sourceImg && this.imageId) {
          this._saveReplaceWithCrop()
        } else {
          // No crop applied — just update focal point
          const payload = {
            mode: 'replace',
            focal_x: Math.round(this.focalX),
            focal_y: Math.round(this.focalY)
          }
          if (this.imageId) payload.image_id = this.imageId
          this.pushEventTo(this.el, 'image_editor_save', payload)
        }
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

  // ── Freeform crop interaction ──────────────────────────────────────

  /**
   * Hit-test the crop rectangle. Returns 'nw', 'ne', 'sw', 'se', 'move', or null.
   */
  hitTestCropRect(displayX, displayY) {
    if (!this.cropRect) return null

    const x = this.cropRect.left * this.displayScale
    const y = this.cropRect.top * this.displayScale
    const w = this.cropRect.width * this.displayScale
    const h = this.cropRect.height * this.displayScale
    const ht = 14 // hit threshold in display pixels

    // Corners
    if (Math.abs(displayX - x) < ht && Math.abs(displayY - y) < ht) return 'nw'
    if (Math.abs(displayX - (x + w)) < ht && Math.abs(displayY - y) < ht) return 'ne'
    if (Math.abs(displayX - x) < ht && Math.abs(displayY - (y + h)) < ht) return 'sw'
    if (Math.abs(displayX - (x + w)) < ht && Math.abs(displayY - (y + h)) < ht) return 'se'

    // Inside
    if (displayX >= x && displayX <= x + w && displayY >= y && displayY <= y + h) return 'move'

    return null
  },

  getCanvasMousePos(e, canvas) {
    const rect = canvas.getBoundingClientRect()
    return {
      x: e.clientX - rect.left,
      y: e.clientY - rect.top
    }
  },

  freeformMouseDown(e, canvas) {
    const pos = this.getCanvasMousePos(e, canvas)

    // Focal pin takes priority — check proximity before crop rect hit test
    const focalDisplayX = (this.focalX / 100) * this.displayW
    const focalDisplayY = (this.focalY / 100) * this.displayH
    const distToFocal = Math.sqrt(
      Math.pow(pos.x - focalDisplayX, 2) + Math.pow(pos.y - focalDisplayY, 2)
    )
    if (distToFocal < 16) {
      this.freeformFocalDrag = true
      return
    }

    const hit = this.hitTestCropRect(pos.x, pos.y)

    if (hit) {
      this.freeformDragState = {
        mode: hit,
        startX: pos.x,
        startY: pos.y,
        startRect: { ...this.cropRect },
        // For corner resize, anchor is the opposite corner in original image coords
        anchor: this.getAnchorForCorner(hit)
      }
    } else {
      // Outside crop rect and not on focal pin: teleport focal to this position
      this.freeformFocalDrag = true
      this.updateFocalFromEvent(e, canvas)
    }
  },

  freeformMouseMove(e, canvas) {
    const pos = this.getCanvasMousePos(e, canvas)

    if (this.freeformDragState) {
      // Actively dragging crop rect
      if (this.freeformDragState.mode === 'move') {
        this.moveCropRect(pos.x, pos.y)
      } else {
        this.resizeCropRect(pos.x, pos.y)
      }
      this.updateAll()
    } else if (this.freeformFocalDrag) {
      // Actively dragging focal point
      canvas.style.cursor = 'grabbing'
      this.updateFocalFromEvent(e, canvas)
    } else {
      // Hover: update cursor — focal pin takes priority
      const focalDisplayX = (this.focalX / 100) * this.displayW
      const focalDisplayY = (this.focalY / 100) * this.displayH
      const distToFocal = Math.sqrt(
        Math.pow(pos.x - focalDisplayX, 2) + Math.pow(pos.y - focalDisplayY, 2)
      )
      if (distToFocal < 16) {
        canvas.style.cursor = 'grab'
      } else {
        const hit = this.hitTestCropRect(pos.x, pos.y)
        this.updateCropCursor(hit, canvas)
      }
    }
  },

  freeformMouseUp() {
    if (this.freeformDragState) {
      this.freeformDragState = null
      this.syncZoomFromCropRect()
    }
    this.freeformFocalDrag = false
  },

  getAnchorForCorner(mode) {
    if (!this.cropRect) return { x: 0, y: 0 }
    const r = this.cropRect
    switch (mode) {
      case 'nw': return { x: r.left + r.width, y: r.top + r.height }
      case 'ne': return { x: r.left, y: r.top + r.height }
      case 'sw': return { x: r.left + r.width, y: r.top }
      case 'se': return { x: r.left, y: r.top }
      default: return { x: 0, y: 0 }
    }
  },

  moveCropRect(displayX, displayY) {
    const ds = this.displayScale
    const state = this.freeformDragState
    const dx = (displayX - state.startX) / ds
    const dy = (displayY - state.startY) / ds

    let left = state.startRect.left + dx
    let top = state.startRect.top + dy

    // Clamp to image bounds
    left = Math.max(0, Math.min(left, this.imageWidth - state.startRect.width))
    top = Math.max(0, Math.min(top, this.imageHeight - state.startRect.height))

    this.cropRect = {
      left: Math.round(left),
      top: Math.round(top),
      width: state.startRect.width,
      height: state.startRect.height
    }
  },

  resizeCropRect(displayX, displayY) {
    const ds = this.displayScale
    const state = this.freeformDragState
    const anchor = state.anchor
    const ratio = this.freeformSelectedRatio
    const minSize = 30

    // Mouse position in original image coords, clamped
    let mx = Math.max(0, Math.min(displayX / ds, this.imageWidth))
    let my = Math.max(0, Math.min(displayY / ds, this.imageHeight))

    // Direction from anchor
    const dirX = (state.mode === 'se' || state.mode === 'ne') ? 1 : -1
    const dirY = (state.mode === 'se' || state.mode === 'sw') ? 1 : -1

    let rawW = (mx - anchor.x) * dirX
    let rawH = (my - anchor.y) * dirY

    rawW = Math.max(minSize, rawW)
    rawH = Math.max(minSize, rawH)

    if (ratio) {
      // Constrain to ratio: use whichever dimension gives a smaller crop
      const hFromW = rawW / ratio
      const wFromH = rawH * ratio

      if (hFromW <= rawH) {
        rawH = hFromW
      } else {
        rawW = wFromH
      }
    }

    let left = dirX > 0 ? anchor.x : anchor.x - rawW
    let top = dirY > 0 ? anchor.y : anchor.y - rawH

    // Clamp to image bounds
    if (left < 0) { rawW += left; left = 0 }
    if (top < 0) { rawH += top; top = 0 }
    if (left + rawW > this.imageWidth) rawW = this.imageWidth - left
    if (top + rawH > this.imageHeight) rawH = this.imageHeight - top

    // Re-constrain ratio after clamping
    if (ratio) {
      const hFromW = rawW / ratio
      const wFromH = rawH * ratio
      if (hFromW <= rawH) {
        rawH = hFromW
      } else {
        rawW = wFromH
      }
    }

    this.cropRect = {
      left: Math.round(left),
      top: Math.round(top),
      width: Math.round(Math.max(minSize, rawW)),
      height: Math.round(Math.max(minSize, rawH))
    }
  },

  /**
   * Resize crop rect from center when zoom slider changes in freeform mode.
   */
  resizeCropRectFromZoom() {
    if (!this.cropRect) return

    const cx = this.cropRect.left + this.cropRect.width / 2
    const cy = this.cropRect.top + this.cropRect.height / 2

    const r = this.freeformSelectedRatio || (this.cropRect.width / this.cropRect.height)

    let maxW, maxH
    if (r >= this.imageWidth / this.imageHeight) {
      maxW = this.imageWidth
      maxH = this.imageWidth / r
    } else {
      maxH = this.imageHeight
      maxW = this.imageHeight * r
    }

    let newW = Math.round(maxW / this.zoom)
    let newH = Math.round(maxH / this.zoom)

    let left = Math.round(cx - newW / 2)
    let top = Math.round(cy - newH / 2)
    left = Math.max(0, Math.min(left, this.imageWidth - newW))
    top = Math.max(0, Math.min(top, this.imageHeight - newH))

    this.cropRect = { left, top, width: newW, height: newH }
  },

  updateCropCursor(hit, canvas) {
    switch (hit) {
      case 'nw': case 'se': canvas.style.cursor = 'nwse-resize'; break
      case 'ne': case 'sw': canvas.style.cursor = 'nesw-resize'; break
      case 'move': canvas.style.cursor = 'move'; break
      default: canvas.style.cursor = 'crosshair'; break
    }
  },

  // ── Configured ratio crop frame interaction ────────────────────────

  /**
   * Hit-test the primary (first) crop frame.
   * Returns 'nw', 'ne', 'sw', 'se', 'move', or null.
   */
  hitTestPrimaryFrame(displayX, displayY) {
    if (this.cropGroups.length === 0) return null

    const region = calculateCropRegion(
      this.focalX, this.focalY,
      this.imageWidth, this.imageHeight,
      this.cropGroups[0].ratio, this.zoom
    )
    const x = region.left * this.displayScale
    const y = region.top * this.displayScale
    const w = region.width * this.displayScale
    const h = region.height * this.displayScale
    const ht = 14

    if (Math.abs(displayX - x) < ht && Math.abs(displayY - y) < ht) return 'nw'
    if (Math.abs(displayX - (x + w)) < ht && Math.abs(displayY - y) < ht) return 'ne'
    if (Math.abs(displayX - x) < ht && Math.abs(displayY - (y + h)) < ht) return 'sw'
    if (Math.abs(displayX - (x + w)) < ht && Math.abs(displayY - (y + h)) < ht) return 'se'
    if (displayX >= x && displayX <= x + w && displayY >= y && displayY <= y + h) return 'move'
    return null
  },

  cropFrameMouseDown(e, canvas) {
    const pos = this.getCanvasMousePos(e, canvas)
    const hit = this.hitTestPrimaryFrame(pos.x, pos.y)

    if (!hit) {
      // Click outside frame: jump focal to clicked position
      this.updateFocalFromEvent(e, canvas)
      return
    }

    const region = calculateCropRegion(
      this.focalX, this.focalY,
      this.imageWidth, this.imageHeight,
      this.cropGroups[0].ratio, this.zoom
    )
    const ds = this.displayScale
    const halfW = (region.width * ds) / 2
    const halfH = (region.height * ds) / 2

    // Corner offset from frame center (used for resize scaling)
    const cornerOffsets = {
      nw: { x: -halfW, y: -halfH },
      ne: { x: +halfW, y: -halfH },
      sw: { x: -halfW, y: +halfH },
      se: { x: +halfW, y: +halfH }
    }

    this.cropFrameDragState = {
      mode: hit,
      startX: pos.x,
      startY: pos.y,
      startFocalX: this.focalX,
      startFocalY: this.focalY,
      startZoom: this.zoom,
      cornerOffset: cornerOffsets[hit] || null
    }
  },

  cropFrameMouseMove(e, canvas) {
    const pos = this.getCanvasMousePos(e, canvas)

    if (!this.cropFrameDragState) {
      // Hover: update cursor
      const hit = this.hitTestPrimaryFrame(pos.x, pos.y)
      this.updateCropCursor(hit, canvas)
      return
    }

    const state = this.cropFrameDragState
    const dx = pos.x - state.startX
    const dy = pos.y - state.startY

    if (state.mode === 'move') {
      // Drag frame interior: shift focal point
      const deltaFocalX = (dx / this.displayW) * 100
      const deltaFocalY = (dy / this.displayH) * 100
      this.focalX = Math.max(0, Math.min(100, state.startFocalX + deltaFocalX))
      this.focalY = Math.max(0, Math.min(100, state.startFocalY + deltaFocalY))
      canvas.style.cursor = 'grabbing'
    } else {
      // Drag corner: scale zoom symmetrically from frame center
      const co = state.cornerOffset
      const startDist = Math.sqrt(co.x ** 2 + co.y ** 2)
      if (startDist > 0) {
        const newDist = Math.sqrt((co.x + dx) ** 2 + (co.y + dy) ** 2)
        const scaleFactor = newDist / startDist
        this.zoom = Math.max(1, Math.min(10, state.startZoom / scaleFactor))
        const slider = this.el.querySelector('#image-editor-zoom')
        if (slider) slider.value = this.zoom.toFixed(2)
        const zoomValue = this.el.querySelector('#image-editor-zoom-value')
        if (zoomValue) zoomValue.textContent = this.zoom.toFixed(2) + 'x'
      }
    }

    this.updateAll()
  },

  cropFrameMouseUp() {
    this.cropFrameDragState = null
  },

  // ── Freeform overlay drawing ───────────────────────────────────────

  drawFreeformOverlay() {
    const overlay = this.el.querySelector('#image-editor-overlay')
    if (!overlay || !this.cropRect) return

    const ctx = overlay.getContext('2d')
    const dpr = window.devicePixelRatio || 1
    const cw = overlay.width / dpr
    const ch = overlay.height / dpr

    ctx.clearRect(0, 0, cw, ch)

    const x = this.cropRect.left * this.displayScale
    const y = this.cropRect.top * this.displayScale
    const w = this.cropRect.width * this.displayScale
    const h = this.cropRect.height * this.displayScale

    // Dim area outside crop
    ctx.fillStyle = 'rgba(0, 0, 0, 0.5)'
    ctx.fillRect(0, 0, cw, ch)
    ctx.clearRect(x, y, w, h)

    // Crop border
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.9)'
    ctx.lineWidth = 1.5
    ctx.setLineDash([])
    ctx.strokeRect(x, y, w, h)

    // Rule-of-thirds grid
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.15)'
    ctx.lineWidth = 0.5
    for (let i = 1; i <= 2; i++) {
      ctx.beginPath()
      ctx.moveTo(x + (w * i) / 3, y)
      ctx.lineTo(x + (w * i) / 3, y + h)
      ctx.stroke()
      ctx.beginPath()
      ctx.moveTo(x, y + (h * i) / 3)
      ctx.lineTo(x + w, y + (h * i) / 3)
      ctx.stroke()
    }

    // Corner handles (L-shapes)
    const cl = Math.min(16, Math.min(w, h) * 0.2)
    ctx.strokeStyle = 'white'
    ctx.lineWidth = 2.5
    ctx.lineCap = 'square'

    // NW
    ctx.beginPath()
    ctx.moveTo(x, y + cl)
    ctx.lineTo(x, y)
    ctx.lineTo(x + cl, y)
    ctx.stroke()

    // NE
    ctx.beginPath()
    ctx.moveTo(x + w - cl, y)
    ctx.lineTo(x + w, y)
    ctx.lineTo(x + w, y + cl)
    ctx.stroke()

    // SW
    ctx.beginPath()
    ctx.moveTo(x, y + h - cl)
    ctx.lineTo(x, y + h)
    ctx.lineTo(x + cl, y + h)
    ctx.stroke()

    // SE
    ctx.beginPath()
    ctx.moveTo(x + w - cl, y + h)
    ctx.lineTo(x + w, y + h)
    ctx.lineTo(x + w, y + h - cl)
    ctx.stroke()
  },

  drawFreeformPreview() {
    if (!this.freeformPreviewCanvas || !this.sourceImg || !this.cropRect) return
    drawCropPreview(this.freeformPreviewCanvas, this.sourceImg, this.cropRect)
  },

  // ── Common update/render methods ───────────────────────────────────

  updateFocalFromEvent(e, canvas) {
    const rect = canvas.getBoundingClientRect()
    const x = Math.max(0, Math.min(100, ((e.clientX - rect.left) / rect.width) * 100))
    const y = Math.max(0, Math.min(100, ((e.clientY - rect.top) / rect.height) * 100))
    this.focalX = x
    this.focalY = y
    this.updateAll()
  },

  updateAll() {
    if (this.freeformMode) {
      this.updateFocalPin()
      this.drawFreeformOverlay()
      this.drawFreeformPreview()
    } else {
      this.updateFocalPin()
      this.updateCropOverlays()
      this.updateCropPreviews()
    }
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

    drawConfiguredOverlays(ctx, regions, this.displayScale)
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

  /**
   * Export the current crop/zoom state to a canvas.
   * Returns the canvas, or null if no crop is applied (full image unchanged).
   * Also recomputes focal from crop center in freeform mode.
   */
  _exportCroppedCanvas() {
    const exportCanvas = document.createElement('canvas')
    const ctx = exportCanvas.getContext('2d')

    if (this.freeformMode && this.cropRect) {
      const r = this.cropRect
      exportCanvas.width = Math.round(r.width)
      exportCanvas.height = Math.round(r.height)
      ctx.drawImage(
        this.sourceImg,
        r.left, r.top, r.width, r.height,
        0, 0, r.width, r.height
      )
      this.focalX = (r.left + r.width / 2) / this.imageWidth * 100
      this.focalY = (r.top + r.height / 2) / this.imageHeight * 100
    } else if (this.cropGroups.length > 0 && this.zoom > 1) {
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
      return null
    }

    return exportCanvas
  },

  /**
   * Upload a cropped canvas blob via HTTP to replace an existing image's file.
   */
  _saveReplaceWithCrop() {
    const exportCanvas = this._exportCroppedCanvas()
    if (!exportCanvas) return

    const focalX = Math.round(this.focalX)
    const focalY = Math.round(this.focalY)
    const imageId = this.imageId
    const csrfToken = document.querySelector('meta[name="csrf-token"]').content
    const hook = this

    exportCanvas.toBlob(async (blob) => {
      if (!blob) return

      const formData = new FormData()
      formData.append('image', new File([blob], 'cropped-image.jpg', { type: 'image/jpeg' }))
      formData.append('image_id', String(imageId))
      formData.append('focal_x', String(focalX))
      formData.append('focal_y', String(focalY))

      try {
        const response = await fetch('/admin/api/content/image/replace_crop', {
          method: 'post',
          headers: {
            'accept': 'application/json, text/javascript, */*; q=0.01',
            'x-csrf-token': csrfToken
          },
          body: formData
        })
        const data = await response.json()

        if (data.status === 200) {
          hook.pushEventTo(hook.el, 'image_editor_save', {
            mode: 'replace',
            focal_x: focalX,
            focal_y: focalY,
            image_id: imageId,
            crop_applied: true
          })
        } else {
          console.error('Error replacing image crop:', data.error)
        }
      } catch (e) {
        console.error('Error replacing image crop:', e)
      }
    }, 'image/jpeg', 0.95)
  },

  closeDrawer() {
    const closeBtn = document.querySelector('#image-editor-drawer .drawer-close-button')
    if (closeBtn) closeBtn.click()
  },

  saveAsNewCopy() {
    // Use shared export, with full-image fallback for "save as new copy"
    let exportCanvas = this._exportCroppedCanvas()

    if (!exportCanvas) {
      exportCanvas = document.createElement('canvas')
      const ctx = exportCanvas.getContext('2d')
      exportCanvas.width = this.imageWidth
      exportCanvas.height = this.imageHeight
      ctx.drawImage(this.sourceImg, 0, 0)
    }

    const focalX = Math.round(this.focalX)
    const focalY = Math.round(this.focalY)

    if (this.fromBlock) {
      const csrfToken = document.querySelector('meta[name="csrf-token"]').content
      const headers = new Headers()
      headers.append('accept', 'application/json, text/javascript, */*; q=0.01')
      headers.append('x-csrf-token', csrfToken)
      const configTarget = this.configTarget

      exportCanvas.toBlob(async (blob) => {
        if (!blob) return

        const file = new File([blob], 'edited-image.jpg', { type: 'image/jpeg' })
        const formData = new FormData()
        formData.append('image', file)
        formData.append('name', file.name)
        formData.append('slug', 'image')
        formData.append('uid', 'image-editor')
        formData.append('formats', '')
        if (configTarget) {
          formData.append('config_target', configTarget)
        }

        try {
          const response = await fetch('/admin/api/content/upload/image', {
            headers,
            method: 'post',
            body: formData,
          })
          const data = await response.json()

          if (data.status === 200) {
            this.pushEventTo(this.el, 'image_editor_new_copy', {
              new_image_id: data.image.id,
              focal_x: focalX,
              focal_y: focalY
            })
          } else {
            console.error('Error creating image copy:', data.error)
          }
        } catch (e) {
          console.error('Error creating image copy:', e)
        }
      }, 'image/jpeg', 0.95)
    } else {
      exportCanvas.toBlob((blob) => {
        if (!blob) return

        const uploadInput = document.querySelector('#image-drawer-form input[type="file"]')
        if (uploadInput) {
          const file = new File([blob], 'cropped-image.jpg', { type: 'image/jpeg' })
          const dataTransfer = new DataTransfer()
          dataTransfer.items.add(file)
          uploadInput.files = dataTransfer.files
          uploadInput.dispatchEvent(new Event('change', { bubbles: true }))

          this.pushEventTo(this.el, 'image_editor_save', {
            mode: 'new_copy',
            focal_x: focalX,
            focal_y: focalY
          })
        }
      }, 'image/jpeg', 0.95)
    }
  }
})
