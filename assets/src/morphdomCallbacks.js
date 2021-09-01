export default {
  onBeforeElUpdated(fromEl, toEl) {
    if (fromEl.isEqualNode(toEl)) {
      return false
    }

    if (fromEl.style.cssText) {
      toEl.style.cssText = fromEl.style.cssText
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