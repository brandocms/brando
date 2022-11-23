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

    return toEl
  }
}
