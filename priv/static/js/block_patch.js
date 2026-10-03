/**
 * Brando block patching
 *
 * Patches rendered blocks into a page in place. Shared by the live preview
 * (`livepreview.js`) and frontend edit mode (`frontend_edit.js`), which both
 * receive HTML for single blocks and whole block fields while an editor types.
 *
 * Blocks are delimited by HTML comments the renderer adds with
 * `annotate_blocks: true`: `[+:B<uid>]` … `[-:B<uid>]` around a block,
 * `[+:C<uid>]` … `[-:C<uid>]` around the children inside it. Frontend edit
 * mode also wraps each block field in `[+:F<key>]` … `[-:F<key>]`.
 *
 * Needs `morphdom` (loaded before this file).
 */
window.BrandoBlockPatch = (function () {
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

  /**
   * The uid in a `[+:B<uid>]`-style marker comment.
   * @param {string} value - The comment's text
   */
  function markerUid(value) {
    return value.substring(value.indexOf('<') + 1, value.indexOf('>'))
  }

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

  function initializeMedia(target) {
    initializeLazyImages(target)
    initializeLazyVideos(target)
  }

  /**
   * Stamp each block's top-level elements with a key morphdom can match on.
   *
   * Blocks are delimited by HTML comments (`[+:B<uid>]` … `[-:B<uid>]`), and
   * comments are invisible to morphdom's matching. With nothing to key on,
   * morphdom pairs `main`'s children up by POSITION, so any structural change —
   * reordering a block, inserting or deleting one above it — makes every element
   * after the change point get rewritten into its neighbour's content. For a
   * video that means the live player is morphed away and a fresh, unbooted
   * container appears in its place: the preview re-initializes a video that never
   * actually changed.
   *
   * Keyed nodes are MOVED instead. morphdom looks the element up by key anywhere
   * in the old tree and relocates it, so a reorder becomes a DOM move and the
   * mounted player survives untouched — as do the `data-smart-video` guards
   * below, which then have a booted player left to protect.
   *
   * Both trees have to be stamped before morphing, or the keys cannot pair up.
   *
   * @param {Node} root - document or parsed document body to stamp
   */
  function stampBlockKeys(root) {
    if (!root || !VALID_TARGET_NODES.includes(root.nodeType)) {
      return
    }

    const iterator = document.createNodeIterator(root, NodeFilter.SHOW_COMMENT, null, false)
    let curNode

    while ((curNode = iterator.nextNode())) {
      const value = curNode.nodeValue.trim()
      if (!value.startsWith('[+:B')) {
        continue
      }

      const uid = markerUid(value)
      let sibling = curNode.nextSibling
      let index = 0
      let safety = 0

      while (sibling && safety++ < 10000) {
        if (
          sibling.nodeType === NODE_TYPES.COMMENT &&
          sibling.nodeValue.trim().startsWith(`[-:B<${uid}`)
        ) {
          break
        }
        if (sibling.nodeType === NODE_TYPES.ELEMENT) {
          sibling.setAttribute('data-lp-key', `${uid}:${index++}`)
        }
        sibling = sibling.nextSibling
      }
    }
  }

  /**
   * An element the host frontend has taken over: a canvas it draws on, a widget
   * it mounted into. Its script sets attributes and children the server's HTML
   * knows nothing about, and morphing would strip them. The template opts in
   * with `data-lp-preserve="<what it shows>"`; while that value is unchanged,
   * the element and its subtree are left as the frontend made them.
   * @param {Element} fromEl - The element in the page
   * @param {Element} toEl - The element in the new HTML
   * @returns {boolean}
   */
  function isPreserved(fromEl, toEl) {
    return fromEl.hasAttribute('data-lp-preserve') &&
      fromEl.getAttribute('data-lp-preserve') === toEl.getAttribute('data-lp-preserve')
  }

  /**
   * Creates a reusable morphdom configuration
   * @param {boolean} childrenOnly - Whether to only update children
   * @returns {Object} - Morphdom configuration object
   */
  function getMorphdomConfig(childrenOnly = true) {
    return {
      // Falls back to morphdom's own default (`node.id`) so anything already
      // relying on ids keeps working.
      getNodeKey(node) {
        if (node.nodeType !== NODE_TYPES.ELEMENT) {
          return undefined
        }
        return node.getAttribute('data-lp-key') || node.id || undefined
      },

      skipFromChildren(fromEl, toEl) {
        // Preserve a live video player's internals when its source is unchanged.
        // A container counts as booted if EITHER the live-preview stub (data-booted)
        // OR the host frontend's real player (data-view-type, set by SmartVideo on
        // init) has claimed it. The frontend boots on full load and marks the
        // container with data-view-type — NOT data-booted — so a full-body rerender
        // that only checked data-booted would re-morph the container, tear out the
        // mounted player, and leave a gray box. Checking both markers keeps booted
        // videos intact across rerender while still re-rendering ones whose source
        // actually changed.
        if (fromEl.hasAttribute('data-smart-video') &&
            (fromEl.hasAttribute('data-booted') || fromEl.hasAttribute('data-view-type')) &&
            fromEl.getAttribute('data-src') === toEl.getAttribute('data-src')) {
          return true
        }
        // Iframes are opaque — never morph their children
        if (fromEl.tagName === 'IFRAME') {
          return true
        }
        if (isPreserved(fromEl, toEl)) {
          return true
        }
        return false
      },

      onBeforeElUpdated(fromEl, toEl) {
        // Skip update if nodes are identical
        if (fromEl.isEqualNode(toEl)) {
          return false
        }

        // Preserve a live video player ENTIRELY when its source is unchanged.
        // The host frontend mounts Vidstack on full load and marks the container
        // with data-view-type (the stub marks it data-booted). Morphing the
        // container at all — even just its attributes — detaches the player and
        // strips the data-view-type marker, leaving a gray box. So a booted player
        // whose source hasn't changed must be a no-op for both the element and its
        // subtree. A genuine source change has no marker match (different data-src)
        // and falls through to re-render normally.
        if (fromEl.hasAttribute('data-smart-video') &&
            (fromEl.hasAttribute('data-booted') || fromEl.hasAttribute('data-view-type')) &&
            fromEl.getAttribute('data-src') === toEl.getAttribute('data-src')) {
          return false
        }

        if (isPreserved(fromEl, toEl)) {
          return false
        }

        // Preserve iframes when src hasn't changed (prevents reload flash)
        if (fromEl.tagName === 'IFRAME' && fromEl.getAttribute('src') === toEl.getAttribute('src')) {
          return false
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

  // Pre-built morphdom configs to avoid creating new objects on every call
  const MORPHDOM_CONFIG_CHILDREN_ONLY = getMorphdomConfig(true)
  const MORPHDOM_CONFIG_FULL = getMorphdomConfig(false)

  /**
   * Build a map of content blocks for efficient updates.
   * Blocks are identified by HTML comments with UIDs.
   * @param {Node} root - Where to look (defaults to document.body)
   * @returns {Map} uid → { uid, elements, insertionPoint, start }
   */
  function buildRegistry(root = document.body) {
    const registry = new Map()
    const iterator = document.createNodeIterator(root, NodeFilter.SHOW_COMMENT, null, false)

    let curNode
    while ((curNode = iterator.nextNode())) {
      if (curNode.nodeValue.trim().startsWith('[+:B')) {
        const uid = markerUid(curNode.nodeValue)
        const blockElements = []

        // Collect all elements until the closing comment
        let sibling = curNode.nextSibling
        let safety = 0
        while (sibling && safety++ < 10000) {
          if (sibling.nodeType === NODE_TYPES.COMMENT && sibling.nodeValue.trim().startsWith(`[-:B<${uid}`)) {
            registry.set(uid, { uid, elements: blockElements, insertionPoint: sibling, start: curNode })
            break
          } else if (sibling.nodeType === NODE_TYPES.ELEMENT) {
            blockElements.push({ element: sibling, children: [] })
          }
          sibling = sibling.nextSibling
        }
      }
    }

    return registry
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

      const iterator = document.createNodeIterator(element, NodeFilter.SHOW_COMMENT, null, false)

      let curNode
      while ((curNode = iterator.nextNode())) {
        if (curNode.nodeValue.trim().startsWith('[+:C')) {
          const uid = markerUid(curNode.nodeValue)

          // Collect children until closing comment
          let sibling = curNode.nextSibling
          let safety = 0
          while (sibling && safety++ < 10000) {
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
    const iterator = document.createNodeIterator(blockElement, NodeFilter.SHOW_TEXT, null, false)
    let curNode

    while ((curNode = iterator.nextNode())) {
      if (curNode.nodeValue.trim().startsWith('[$ content $]')) {
        return curNode
      }
    }
    return null
  }

  /**
   * Parse a block's HTML as a fragment, the way it sits in the page.
   *
   * `DOMParser` parses a whole document: a leading `<style>`, `<script>`, `<link>`
   * or `<meta>` is moved into its `<head>`, and table rows outside a table are
   * dropped, so a block starting with any of them lost it on its first edit.
   * A `<template>` keeps them in place.
   * @param {string} html
   * @returns {Element[]} The fragment's top-level elements
   */
  function parseFragment(html) {
    const template = document.createElement('template')
    template.innerHTML = html
    return Array.from(template.content.childNodes).filter(node => node.nodeType === NODE_TYPES.ELEMENT)
  }

  /**
   * Tell the site's own scripts what the preview just changed.
   *
   * The site's JS initialised the page once, on load. Elements patched in or
   * inserted afterwards — a slider, a lightbox, a canvas whose `data-lp-preserve`
   * value changed — are never initialised again unless the site listens:
   *
   *   document.addEventListener('brando:livepreview:patched', ({ detail }) => {
   *     detail.elements.forEach(el => initWidgets(el))
   *   })
   *
   * `detail.type` is `block` (one block, with its `uid`; no elements when it was
   * removed), `update` (`<main>`), `rerender` (`<body>`) or `field` (a block
   * field in frontend edit mode). `detail.source` is `livepreview` or
   * `frontend-edit`.
   */
  function announcePatch(type, elements, uid, source = 'livepreview') {
    document.dispatchEvent(
      new CustomEvent('brando:livepreview:patched', { detail: { type, uid, elements, source } })
    )
  }

  /**
   * Patch one block's new HTML into its place in the page.
   *
   * @param {Map} registry - From `buildRegistry`; updated in place
   * @param {Object} payload - `{ uid, rendered_html, has_children }`
   * @returns {Element[]|null} The block's elements after the patch, or null when
   *   the block is not on the page
   */
  function patchBlock(registry, { uid, rendered_html, has_children }) {
    const block = registry.get(uid)

    if (!block) {
      return null
    }

    // Handle empty content (removed blocks)
    if (rendered_html === '') {
      block.elements.forEach(el => el.element.remove())
      block.elements = []
      return []
    }

    // Parse new content. `buildRegistry` only tracks ELEMENT nodes, so the
    // parsed nodes are filtered the same way or the two lists do not line up:
    // index 0 would pair the `[+:B<uid>]` boundary comment against the block's
    // first element, the nodeType check below would fail, and the replace
    // branch would drop the live element without ever running the child
    // splice — which is how a multi-module's children vanished from the preview.
    const newBlocks = parseFragment(rendered_html)

    // Update children map if needed
    if (has_children) {
      block.elements = mapNestedContent(block.elements)
    }

    // Handle new blocks (no existing elements)
    if (!block.elements.length) {
      newBlocks.forEach((newBlock, idx) => {
        const newElement = block.insertionPoint.parentNode.insertBefore(newBlock, block.insertionPoint)

        block.elements[idx] = { element: newElement }
        initializeMedia(newElement)
      })
    } else {
      // Update existing blocks
      const newEls = []

      newBlocks.forEach((newBlock, idx) => {
        const existingEl = block.elements[idx]

        if (existingEl && existingEl.element.nodeType === newBlock.nodeType) {
          // Update existing element with morphdom. When the tag changes, morphdom
          // replaces the node and returns the new one; keeping the old reference
          // left the registry pointing at a detached node, so the block's next
          // update went nowhere.
          existingEl.element = morphdom(existingEl.element, newBlock, MORPHDOM_CONFIG_FULL)

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
          initializeMedia(existingEl.element)
        } else {
          // Replace element if types don't match
          const newElement = block.insertionPoint.parentNode.insertBefore(newBlock, block.insertionPoint)

          if (existingEl) {
            existingEl.element.remove()
          }

          newEls.push({ element: newElement })
          initializeMedia(newElement)
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

    return block.elements.map(el => el.element)
  }

  /**
   * The `[+:F<key>]` … `[-:F<key>]` comments around a block field, or null.
   * @param {string} key
   * @param {Node} root
   */
  function findField(key, root = document.body) {
    const iterator = document.createNodeIterator(root, NodeFilter.SHOW_COMMENT, null, false)
    let start = null
    let curNode

    while ((curNode = iterator.nextNode())) {
      const value = curNode.nodeValue.trim()
      if (!start && value === `[+:F<${key}>]`) {
        start = curNode
      } else if (start && value === `[-:F<${key}>]`) {
        return { start, end: curNode }
      }
    }

    return null
  }

  /**
   * Replace everything between a field's markers with new HTML.
   *
   * morphdom needs one root to morph, and the field shares its parent with
   * whatever the template put around it. So the parent is copied with the
   * field's nodes swapped for the new ones and morphed into the page, children
   * only: the surrounding nodes are copies of themselves and stay as they are,
   * and keyed block elements are matched and moved, keeping mounted players.
   *
   * @param {string} key - The field key
   * @param {string} html - The field's new HTML, without its own markers
   * @returns {Element|null} The parent that was patched, or null when the field
   *   is not on the page
   */
  function replaceField(key, html) {
    const field = findField(key)
    if (!field || field.start.parentNode !== field.end.parentNode) {
      return null
    }

    const parent = field.start.parentNode
    const next = parent.cloneNode(false)
    let node = parent.firstChild
    let inField = false

    while (node) {
      if (node === field.start) {
        next.appendChild(node.cloneNode(false))
        const template = document.createElement('template')
        template.innerHTML = html
        next.appendChild(template.content)
        inField = true
      } else if (node === field.end) {
        next.appendChild(node.cloneNode(false))
        inField = false
      } else if (!inField) {
        next.appendChild(node.cloneNode(true))
      }
      node = node.nextSibling
    }

    stampBlockKeys(parent)
    stampBlockKeys(next)
    morphdom(parent, next, MORPHDOM_CONFIG_CHILDREN_ONLY)
    initializeMedia(parent)
    return parent
  }

  return {
    NODE_TYPES,
    markerUid,
    initializeLazyImages,
    initializeLazyVideos,
    initializeMedia,
    stampBlockKeys,
    isPreserved,
    getMorphdomConfig,
    MORPHDOM_CONFIG_CHILDREN_ONLY,
    MORPHDOM_CONFIG_FULL,
    buildRegistry,
    mapNestedContent,
    findContentInsertionMarker,
    parseFragment,
    announcePatch,
    patchBlock,
    findField,
    replaceField
  }
})()
