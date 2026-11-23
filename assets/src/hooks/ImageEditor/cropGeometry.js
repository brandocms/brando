/**
 * Where the server cuts a crop from the original, for the image editor's frames.
 *
 * A focal point is `x` and `y` percentages of the image, read by its mode the
 * way `Brando.Images.Operations.Sizing.calculate_anchor/1` reads it:
 *
 *   - `center`: the frame is centred on the point.
 *   - `position`: the frame lines up with the image the way CSS
 *     `object-position` does, splitting the part it leaves out of an axis
 *     `p : (100 - p)`.
 *
 * Either way the frame stays inside the image.
 */

/**
 * Calculate the crop region for a ratio and a focal point.
 *
 * @param {number} focalX - Focal X in percentage (0-100)
 * @param {number} focalY - Focal Y in percentage (0-100)
 * @param {number} origWidth - Original image width in pixels
 * @param {number} origHeight - Original image height in pixels
 * @param {number} targetRatio - Target crop aspect ratio (width / height)
 * @param {number} zoom - Zoom level (1 = full, >1 = tighter crop)
 * @param {'center'|'position'} [mode] - How the focal point places the frame
 * @returns {{ left: number, top: number, width: number, height: number }}
 */
export function calculateCropRegion(focalX, focalY, origWidth, origHeight, targetRatio, zoom, mode = 'center') {
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

  return {
    left: anchorOnAxis(focalX, origWidth, cropWidth, mode),
    top: anchorOnAxis(focalY, origHeight, cropHeight, mode),
    width: cropWidth,
    height: cropHeight
  }
}

function anchorOnAxis(focal, image, frame, mode) {
  const anchor = mode === 'position'
    ? Math.round((focal / 100) * (image - frame))
    : Math.round((focal / 100) * image - frame / 2)

  return Math.min(Math.max(0, anchor), image - frame)
}

/**
 * The centre-mode focal point that places a frame where it stands: its centre,
 * in percent of the image.
 *
 * @param {{ left: number, top: number, width: number, height: number }} region
 * @param {number} origWidth - Original image width in pixels
 * @param {number} origHeight - Original image height in pixels
 * @returns {{ x: number, y: number }}
 */
export function centerFocalOf(region, origWidth, origHeight) {
  return {
    x: ((region.left + region.width / 2) / origWidth) * 100,
    y: ((region.top + region.height / 2) / origHeight) * 100
  }
}

/**
 * Move a centre-mode focal point along one axis by however far its crop frame
 * can follow.
 *
 * `calculateCropRegion` centres the frame on the focal and then clamps it to the
 * image, so the frame stops at the edges while the focal has plenty of room
 * left. Dragging the frame has to be measured in the frame's movement rather
 * than the pointer's, or the two come apart at exactly the edges where a crop is
 * usually set.
 *
 * @param {number} focal - Focal position on this axis, 0-100
 * @param {number} delta - Pointer movement in original-image pixels
 * @param {number} frame - Frame size on this axis, in original-image pixels
 * @param {number} image - Image size on this axis, in original-image pixels
 * @returns {number} The new focal position, 0-100
 */
export function shiftFocalWithFrame(focal, delta, frame, image) {
  const span = image - frame
  if (span <= 0) return focal // frame fills the axis: nothing to drag

  const start = Math.min(Math.max((focal / 100) * image - frame / 2, 0), span)
  const moved = Math.min(Math.max(start + delta, 0), span) - start

  return Math.min(100, Math.max(0, focal + (moved / image) * 100))
}

/**
 * Re-express a focal point in the coordinates of a region exported from the image.
 *
 * The focal is a percentage of the image it is stored on, and after a crop that
 * image is the region — so a focal left in the original's coordinates points
 * somewhere else entirely. Measured against the original, cropping the top
 * left quarter of a 1000x800 image would save (25, 25) for a file whose centre
 * is by definition (50, 50), and every `crop: true` size derived from it would
 * be anchored toward the corner. The square `thumb` is the one that shows it
 * worst, and `build_crop_groups/1` filters it out of the previews, so nothing
 * in the editor would show the damage either.
 *
 * The pin keeps its place on the photo in either mode. For a position-mode
 * point that leaves the percentages as they were, so the server cuts the
 * other sizes from the exported file where the editor showed them.
 *
 * @param {number} focalX - Focal X in percentage of the original (0-100)
 * @param {number} focalY - Focal Y in percentage of the original (0-100)
 * @param {{ left: number, top: number, width: number, height: number }} region
 * @param {number} origWidth - Original image width in pixels
 * @param {number} origHeight - Original image height in pixels
 * @returns {{ x: number, y: number }}
 */
export function focalInRegion(focalX, focalY, region, origWidth, origHeight) {
  const toPercent = (px, start, size) => Math.max(0, Math.min(100, ((px - start) / size) * 100))

  return {
    x: toPercent((focalX / 100) * origWidth, region.left, region.width),
    y: toPercent((focalY / 100) * origHeight, region.top, region.height)
  }
}
