/**
 * Brando CMS Live Preview
 * 
 * This module handles real-time preview updates for the Brando CMS admin interface.
 * It connects to a Phoenix socket channel and updates the DOM efficiently using morphdom
 * when content changes are broadcast from the server.
 */

// Initialize live preview environment
document.documentElement.classList.add('is-live-preview')

// DOM Node Type Constants
const NODE_TYPES = {
  ELEMENT: 1,
  TEXT: 3,
  COMMENT: 8,
  DOCUMENT: 9,
  DOCUMENT_FRAGMENT: 11
}

// Valid node types for lazy loading operations
const VALID_TARGET_NODES = [NODE_TYPES.ELEMENT, NODE_TYPES.DOCUMENT, NODE_TYPES.DOCUMENT_FRAGMENT]

// Cache DOM references
const token = document.querySelector('meta[name="user_token"]').getAttribute('content')
const main = document.querySelector('main')
const body = document.querySelector('body')
const parser = new DOMParser()

// Phoenix Socket connection
const previewSocket = new Phoenix.Socket('/admin/socket', {
  params: { token: token },
})
previewSocket.connect()

const channel = previewSocket.channel('live_preview:' + livePreviewKey)

// State management
let isFirstUpdate = true
let contentBlockRegistry = []

// CSS overrides for live preview to ensure visibility of animated elements
const MOONWALK_OVERRIDE_STYLES = `
  .is-live-preview [data-moonwalk],
  .is-live-preview [data-moonwalk-run],
  .is-live-preview [data-moonwalk-section],
  .is-live-preview [data-moonwalk-children] > *,
  .is-live-preview [b-section] {
    opacity: 1 !important;
    transform: none !important;
    visibility: visible !important;
  }
  .is-live-preview [data-smart-video][data-revealed] {
    opacity: 1 !important;
    visibility: visible !important;
  }
`

/**
 * Force lazy-loaded images to load immediately
 * @param {Node} target - The DOM node to search within (defaults to document)
 */
function initializeLazyImages(target = document) {
  // Ensure target is a valid element node
  if (!VALID_TARGET_NODES.includes(target.nodeType)) {
    return
  }

  // Load images with data-ll-image or data-ll-srcset-image attributes
  target
    .querySelectorAll('[data-ll-image]:not([data-ll-loaded]), [data-ll-srcset-image]:not([data-ll-loaded])')
    .forEach(lazyImage => {
      if (lazyImage.dataset.src) {
        lazyImage.src = lazyImage.dataset.src
      }
      if (lazyImage.dataset.srcset) {
        lazyImage.srcset = lazyImage.dataset.srcset
      }
      lazyImage.dataset.llLoaded = ''
    })

  // Initialize srcset elements
  target
    .querySelectorAll('[data-ll-srcset]:not([data-data-ll-srcset-initialized])')
    .forEach(lazySrcSet => {
      lazySrcSet.dataset.llSrcsetInitialized = ''
    })
}

/**
 * Force lazy-loaded videos to load immediately
 * Only processes new videos that haven't been initialized
 * @param {Node} target - The DOM node to search within (defaults to document)
 */
function initializeLazyVideos(target = document) {
  // Ensure target is a valid element node
  if (!VALID_TARGET_NODES.includes(target.nodeType)) {
    return
  }

  // Initialize video elements that haven't been booted
  target.querySelectorAll('[data-smart-video] video:not([data-booted])').forEach(videoElement => {
    // Only set src if data-src exists and src is not already set
    if (videoElement.dataset.src && !videoElement.src) {
      videoElement.src = videoElement.dataset.src
    }
    videoElement.dataset.booted = ''
  })

  // Initialize smart video containers
  target.querySelectorAll('[data-smart-video]:not([data-revealed])').forEach(videoContainer => {
    videoContainer.dataset.revealed = ''
    videoContainer.dataset.booted = ''
    videoContainer.dataset.playing = ''
  })
}

/**
 * NodeFilter helper for createNodeIterator
 * @returns {number} - Always accepts the node
 */
function filterNone() {
  return NodeFilter.FILTER_ACCEPT
}

/**
 * Creates a reusable morphdom configuration
 * @param {boolean} childrenOnly - Whether to only update children
 * @returns {Object} - Morphdom configuration object
 */
function getMorphdomConfig(childrenOnly = true) {
  return {
    onBeforeElUpdated: (fromEl, toEl) => {
      // Skip update if nodes are identical
      if (fromEl.isEqualNode(toEl)) {
        return false
      }

      // Preserve smart video elements if source hasn't changed
      if (fromEl.hasAttribute('data-smart-video') && toEl.hasAttribute('data-smart-video')) {
        if (fromEl.getAttribute('data-src') === toEl.getAttribute('data-src')) {
          return false
        }
      }

      // Handle lazy-loaded images
      if (fromEl.dataset.src && toEl.dataset.src) {
        // Compare image URLs without query parameters
        const fromSrc = fromEl.dataset.src.split('?')[0]
        const toSrc = toEl.dataset.src.split('?')[0]
        
        if (fromSrc === toSrc && toEl.dataset.llLoaded) {
          return false
        }

        // Update src if data-src has changed
        toEl.src = toEl.dataset.src
      }

      return true
    },
    childrenOnly: childrenOnly,
  }
}

/**
 * Build a map of content blocks for efficient updates
 * Blocks are identified by HTML comments with UIDs
 */
function rebuildContentBlockRegistry() {
  contentBlockRegistry = []
  const iterator = document.createNodeIterator(
    document.body,
    NodeFilter.SHOW_COMMENT,
    filterNone,
    false
  )

  let curNode
  while ((curNode = iterator.nextNode())) {
    if (curNode.nodeValue.trim().startsWith('[+:B')) {
      // Extract UID from comment
      const uidStart = curNode.nodeValue.indexOf('<')
      const uidEnd = curNode.nodeValue.indexOf('>')
      const uid = curNode.nodeValue.substring(uidStart + 1, uidEnd)
      const blockElements = []
      
      // Collect all elements until the closing comment
      let sibling = curNode.nextSibling
      while (sibling) {
        if (sibling.nodeType === NODE_TYPES.COMMENT && sibling.nodeValue.trim().startsWith(`[-:B<${uid}`)) {
          contentBlockRegistry.push({ uid, elements: blockElements, insertionPoint: sibling })
          break
        } else if (sibling.nodeType === NODE_TYPES.ELEMENT) {
          blockElements.push({ element: sibling, children: [] })
        }
        sibling = sibling.nextSibling
      }
    }
  }
}

/**
 * Map nested content within block elements
 * @param {Array} blockElements - Array of element objects
 * @returns {Array} - Elements with their children mapped
 */
function mapNestedContent(blockElements) {
  return blockElements.map(blockEl => {
    const element = blockEl.element
    const childNodes = []

    const iterator = document.createNodeIterator(
      element,
      NodeFilter.SHOW_COMMENT,
      filterNone,
      false
    )

    let curNode
    while ((curNode = iterator.nextNode())) {
      if (curNode.nodeValue.trim().startsWith('[+:C')) {
        // Extract UID from comment
        const uidStart = curNode.nodeValue.indexOf('<')
        const uidEnd = curNode.nodeValue.indexOf('>')
        const uid = curNode.nodeValue.substring(uidStart + 1, uidEnd)

        // Collect children until closing comment
        let sibling = curNode.nextSibling
        while (sibling) {
          if (sibling.nodeType === NODE_TYPES.COMMENT && sibling.nodeValue.trim().startsWith(`[-:C<${uid}`)) {
            blockEl.childInsertionPoint = sibling
            break
          } else {
            childNodes.push(sibling)
          }
          sibling = sibling.nextSibling
        }
      }
    }
    
    blockEl.children = childNodes
    return blockEl
  })
}

/**
 * Find the content insertion point within a block
 * @param {Node} blockElement - The block element to search within
 * @returns {Node|null} - The text node marking the insertion point
 */
function findContentInsertionMarker(blockElement) {
  const iterator = document.createNodeIterator(blockElement, NodeFilter.SHOW_TEXT, filterNone, false)
  let curNode

  while ((curNode = iterator.nextNode())) {
    if (curNode.nodeValue.trim().startsWith('[$ content $]')) {
      return curNode
    }
  }
  return null
}

/**
 * Insert animation override styles on first update
 */
function insertOverrideStyles() {
  if (isFirstUpdate) {
    const style = document.createElement('style')
    style.innerHTML = MOONWALK_OVERRIDE_STYLES
    document.head.appendChild(style)
    isFirstUpdate = false
  }
}

/**
 * Handle individual block updates
 */
channel.on('update_block', function ({ uid, rendered_html, has_children }) {
  insertOverrideStyles()

  // Find the block in our map
  let blockIndex = contentBlockRegistry.findIndex(block => block.uid === uid)
  
  // If not found, rebuild the map and try again
  if (blockIndex === -1) {
    rebuildContentBlockRegistry()
    blockIndex = contentBlockRegistry.findIndex(block => block.uid === uid)
  }

  if (blockIndex === -1) {
    return // Block not found
  }

  const block = contentBlockRegistry[blockIndex]

  // Handle empty content (removed blocks)
  if (rendered_html === '') {
    block.elements.forEach(el => el.element.remove())
    block.elements = []
    return
  }

  // Parse new content
  const doc = parser.parseFromString(rendered_html, 'text/html')
  const newBlocks = Array.from(doc.querySelector('body').childNodes)

  // Update children map if needed
  if (has_children) {
    block.elements = mapNestedContent(block.elements)
  }

  // Handle new blocks (no existing elements)
  if (!block.elements.length) {
    newBlocks.forEach((newBlock, idx) => {
      // Skip comment nodes that mark block boundaries
      if (newBlock.nodeType === NODE_TYPES.COMMENT && newBlock.nodeValue.trim().startsWith(`[-:B<${block.uid}`)) {
        return
      }

      const newElement = block.insertionPoint.parentNode.insertBefore(
        newBlock,
        block.insertionPoint
      )

      block.elements[idx] = { element: newElement }
      initializeLazyImages(newElement)
      initializeLazyVideos(newElement)
    })
  } else {
    // Update existing blocks
    const newEls = []

    newBlocks.forEach((newBlock, idx) => {
      // Skip comment nodes that mark block boundaries
      if (newBlock.nodeType === NODE_TYPES.COMMENT && newBlock.nodeValue.trim().startsWith(`[-:B<${block.uid}`)) {
        return
      }

      const existingEl = block.elements[idx]

      if (existingEl && existingEl.element.nodeType === newBlock.nodeType) {
        // Update existing element with morphdom
        morphdom(existingEl.element, newBlock, getMorphdomConfig(false))

        // Handle nested children
        if (has_children && existingEl.children) {
          const childInsertionPoint = findContentInsertionMarker(existingEl.element)
          if (childInsertionPoint) {
            existingEl.children.forEach(child => {
              // Skip boundary comments
              if (child.nodeType === NODE_TYPES.COMMENT && child.nodeValue.trim().startsWith(`[-:C<${block.uid}`)) {
                return
              }
              childInsertionPoint.parentNode.insertBefore(child, childInsertionPoint)
            })
            childInsertionPoint.remove()
          }
        }

        newEls.push(existingEl)
        initializeLazyImages(existingEl.element)
        initializeLazyVideos(existingEl.element)
      } else {
        // Replace element if types don't match
        const newElement = block.insertionPoint.parentNode.insertBefore(
          newBlock,
          block.insertionPoint
        )

        if (existingEl) {
          existingEl.element.remove()
        }

        newEls.push({ element: newElement })
        initializeLazyImages(newElement)
        initializeLazyVideos(newElement)
      }
    })

    // Clean up any extra old elements
    for (let idx = newEls.length; idx < block.elements.length; idx++) {
      if (block.elements[idx]) {
        block.elements[idx].element.remove()
      }
    }

    block.elements = newEls
  }
})

/**
 * Handle full page updates (main content only)
 */
channel.on('update', function (payload) {
  document.documentElement.classList.add('is-updated-live-preview')
  
  const doc = parser.parseFromString(payload.html, 'text/html')
  const newMain = doc.querySelector('main')
  
  morphdom(main, newMain, getMorphdomConfig(true))

  initializeLazyImages()
  initializeLazyVideos()
  rebuildContentBlockRegistry()
})

/**
 * Handle full page re-renders (entire body)
 */
channel.on('rerender', function (payload) {
  insertOverrideStyles()
  document.documentElement.classList.add('is-updated-live-preview')
  
  const doc = parser.parseFromString(payload.html, 'text/html')
  const newBody = doc.querySelector('body')

  morphdom(body, newBody, getMorphdomConfig(false))

  initializeLazyImages()
  initializeLazyVideos()
  rebuildContentBlockRegistry()

  body.classList.remove('unloaded')
})

// Connect to the channel
channel.join()