/* Add live preview class to html */
document.documentElement.classList.add('is-live-preview')
var token = document.querySelector('meta[name="user_token"]').getAttribute('content')
var previewSocket = new Phoenix.Socket('/admin/socket', { params: { token: token } })
var main = document.querySelector('main')
var parser = new DOMParser()
previewSocket.connect()
var channel = previewSocket.channel('live_preview:' + livePreviewKey)
var firstUpdate = true

function forceLazyloadAllImages() {
  document
    .querySelectorAll(
      '[data-ll-image]:not([data-ll-loaded]), [data-ll-srcset-image]:not([data-ll-loaded])'
    )
    .forEach(llImage => {
      llImage.src = llImage.dataset.src
      if (llImage.dataset.srcset) {
        llImage.srcset = llImage.dataset.srcset
      }
      llImage.src = llImage.dataset.src
      llImage.dataset.llLoaded = ''
    })
}

function forceLazyloadAllVideos() {
  document.querySelectorAll('[data-smart-video] video:not([data-booted])').forEach(llVideo => {
    llVideo.src = llVideo.dataset.src
    llVideo.dataset.booted = ''
  })
}

var blockMap = []

function filterNone() {
  return NodeFilter.FILTER_ACCEPT
}

var uid

function buildMap() {
  blockMap = []
  console.log('==> building map..')
  var iterator = document.createNodeIterator(
    document.body,
    NodeFilter.SHOW_COMMENT,
    filterNone,
    false
  )

  var curNode

  while ((curNode = iterator.nextNode())) {
    if (curNode.nodeValue.trim().startsWith('B:LP')) {
      // extract uid
      var uidStart = curNode.nodeValue.indexOf('{')
      var uidEnd = curNode.nodeValue.indexOf('}')
      var uid = curNode.nodeValue.substring(uidStart + 1, uidEnd)
      var els = []
      // loop through the next siblings until we find the end comment
      let sibling = curNode.nextSibling
      while (sibling) {
        if (sibling.nodeType === 8 && sibling.nodeValue.trim().startsWith(`E:LP{${uid}`)) {
          blockMap.push({ uid, els, insertionPoint: sibling })
          els = []
          break
        } else if (sibling.nodeType === 1) {
          els.push({ element: sibling, children: [] })
          sibling = sibling.nextSibling
        } else {
          sibling = sibling.nextSibling
        }
      }
    }
  }
  console.log('==> blockMap', blockMap)
}

buildMap()

function getChildren(els) {
  return els.map(el => {
    var element = el.element
    var elChildren = []

    var iterator = document.createNodeIterator(
      element,
      NodeFilter.SHOW_COMMENT,
      filterNone,
      false
    )

    var curNode

    while ((curNode = iterator.nextNode())) {
      if (curNode.nodeValue.trim().startsWith('B:CHILDREN')) {
        // extract uid
        var uidStart = curNode.nodeValue.indexOf('{')
        var uidEnd = curNode.nodeValue.indexOf('}')
        var uid = curNode.nodeValue.substring(uidStart + 1, uidEnd)

        // loop through the next siblings until we find the end comment
        let sibling = curNode.nextSibling
        while (sibling) {
          if (
            sibling.nodeType === 8 &&
            sibling.nodeValue.trim().startsWith(`E:CHILDREN{${uid}`)
          ) {
            el.childInsertionPoint = sibling
            break
          } else if (sibling.nodeType === 1) {
            elChildren.push(sibling)
            sibling = sibling.nextSibling
          } else {
            elChildren.push(sibling)
            sibling = sibling.nextSibling
          }
        }
      }
    }
    console.log('=> adding children to element', el, elChildren)
    el.children = elChildren
    return el
  })
}

function getInsertionPoint(newBlock, uid) {
  var iterator = document.createNodeIterator(newBlock, NodeFilter.SHOW_TEXT, filterNone, false)
  var curNode

  while ((curNode = iterator.nextNode())) {
    console.log('scanning', curNode.nodeValue.trim())
    if (curNode.nodeValue.trim().startsWith('{$ content $}')) {
      console.log('found insertion point', curNode, curNode.nodeType)
      break
    }
  }
  return curNode
}

channel.on('update_block', function ({ uid, rendered_html, has_children }) {
  if (firstUpdate) {
    // insert styles to head
    var style = document.createElement('style')
    style.innerHTML = `
      .is-live-preview [data-moonwalk],
      .is-live-preview [data-moonwalk-run], 
      .is-live-preview [data-moonwalk-section], 
      .is-live-preview [b-section] {
        opacity: 1 !important;
        visibility: visible !important;
      }
    `
    document.head.appendChild(style)
  }

  var blockIndex = blockMap.findIndex(block => block.uid === uid)
  if (blockIndex >= 0) {
    var block = blockMap[blockIndex]
    if (rendered_html === '') {
      block.els.forEach((el, idx) => {
        el.element.remove()
      })
      return
    }

    var doc = parser.parseFromString(rendered_html, 'text/html')
    var newBlocks = doc.querySelector('body').childNodes

    if (has_children) {
      var elsWithChildren = getChildren(block.els)
      block.els = elsWithChildren
    }

    block.els.forEach((el, idx) => {
      if (has_children) {
        // find insertion point of the new element
        var childInsertionPoint = getInsertionPoint(newBlocks[idx], block.uid)

        // insert children at childInsertionPoint
        for (var i = 0; i < el.children.length; i++) {
          childInsertionPoint.parentNode.insertBefore(el.children[i], childInsertionPoint)
        }

        childInsertionPoint.remove()

        var newElement = block.insertionPoint.parentNode.insertBefore(
          newBlocks[idx],
          block.insertionPoint
        )
      } else {
        var newElement = block.insertionPoint.parentNode.insertBefore(
          newBlocks[idx],
          block.insertionPoint
        )
      }
      console.log('el -- we are removing .element', el)
      el.element.remove()

      console.log('added', newElement)
      block.els[idx].element = newElement
    })

    forceLazyloadAllImages()
    forceLazyloadAllVideos()
  }
})

channel.on('update', function (payload) {
  document.documentElement.classList.add('is-updated-live-preview')
  var doc = parser.parseFromString(payload.html, 'text/html')
  var newMain = doc.querySelector('main')
  morphdom(main, newMain, {
    onBeforeElUpdated: (a, b) => {
      if (a.isEqualNode(b)) {
        return false
      }

      if (a.dataset.src && b.dataset.src) {
        if (a.dataset.src.split('?')[0] === b.dataset.src.split('?')[0] && b.dataset.llLoaded) {
          return false
        }

        // data-src differ. Update src
        b.src = b.dataset.src
      }

      return true
    },
    childrenOnly: true
  })

  forceLazyloadAllImages()
  forceLazyloadAllVideos()

  buildMap()
})
channel.join()
