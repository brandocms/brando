
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
    
    // console.log('fromEl.innerHTML === toEl.innerHTML', fromEl.innerHTML === toEl.innerHTML)
    // console.log('doing something from =>', fromEl.innerHTML)
    // console.log('doing something to =>', toEl.innerHTML)

    // if (fromEl.innerHTML.includes('article-credits-rich-text-target-wrapper')) {
    //   console.log('fromEl.innerHTML === toEl.innerHTML', fromEl.innerHTML === toEl.innerHTML)
    //   console.log('doing something from =>', fromEl.innerHTML)
    //   console.log('doing something to =>', toEl.innerHTML)
    // }

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