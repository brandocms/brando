
export default {
  onBeforeElUpdated(fromEl, toEl) {
    if (fromEl.isEqualNode(toEl)) {
      return false
    }
    
    if (fromEl.className === 'tiptap-wrapper') {
      return false
    }
    
    if (fromEl.className === 'tiptap-menu') {
      return false
    }

    if (fromEl.style.cssText) {
      toEl.style.cssText = !toEl.style.cssText ? fromEl.style.cssText : toEl.style.cssText
    }

    if (fromEl.hasAttribute('data-b-hover')) {
      toEl.dataset.bHover = ''
    }

    if (fromEl.hasAttribute('data-b-loaded')) {
      toEl.dataset.bLoaded = ''
    }

    return toEl
  }
}