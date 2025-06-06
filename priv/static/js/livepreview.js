console.log('Live Preview')
/* Add live preview class to html */
document.documentElement.classList.add('is-live-preview')
var token = document
  .querySelector('meta[name="user_token"]')
  .getAttribute('content')
var previewSocket = new Phoenix.Socket('/admin/socket', {
  params: { token: token },
})
var main = document.querySelector('main')
var body = document.querySelector('body')
var parser = new DOMParser()
previewSocket.connect()
var channel = previewSocket.channel('live_preview:' + livePreviewKey)
var firstUpdate = true
var MOONWALK_OVERRIDE_STYLES = `
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

function forceLazyloadAllImages(target = document) {
  // ensure target is an element, not comment
  if (![1, 9, 11].includes(target.nodeType)) {
    return
  }
  target
    .querySelectorAll(
      '[data-ll-image]:not([data-ll-loaded]), [data-ll-srcset-image]:not([data-ll-loaded])'
    )
    .forEach((llImage) => {
      llImage.src = llImage.dataset.src
      if (llImage.dataset.srcset) {
        llImage.srcset = llImage.dataset.srcset
      }
      llImage.src = llImage.dataset.src
      llImage.dataset.llLoaded = ''
    })

  target
    .querySelectorAll('[data-ll-srcset]:not([data-data-ll-srcset-initialized])')
    .forEach((llSrcSet) => {
      llSrcSet.dataset.llSrcsetInitialized = ''
    })
}

function forceLazyloadAllVideos(target = document) {
  if (![1, 9, 11].includes(target.nodeType)) {
    return
  }

  target
    .querySelectorAll('[data-smart-video] video:not([data-booted])')
    .forEach((llVideo) => {
      llVideo.src = llVideo.dataset.src
      llVideo.dataset.booted = ''
    })

  target
    .querySelectorAll('[data-smart-video]:not([data-revealed])')
    .forEach((llVideo) => {
      llVideo.dataset.revealed = ''
      llVideo.dataset.booted = ''
      llVideo.dataset.playing = ''
    })
}

var blockMap = []

function filterNone() {
  return NodeFilter.FILTER_ACCEPT
}

var uid

function buildMap() {
  blockMap = []
  var iterator = document.createNodeIterator(
    document.body,
    NodeFilter.SHOW_COMMENT,
    filterNone,
    false
  )

  var curNode

  while ((curNode = iterator.nextNode())) {
    if (curNode.nodeValue.trim().startsWith('[+:B')) {
      // extract uid
      var uidStart = curNode.nodeValue.indexOf('<')
      var uidEnd = curNode.nodeValue.indexOf('>')
      var uid = curNode.nodeValue.substring(uidStart + 1, uidEnd)
      var els = []
      // loop through the next siblings until we find the end comment
      let sibling = curNode.nextSibling
      while (sibling) {
        if (
          sibling.nodeType === 8 &&
          sibling.nodeValue.trim().startsWith(`[-:B<${uid}`)
        ) {
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
}

buildMap()

function getChildren(els) {
  return els.map((el) => {
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
      if (curNode.nodeValue.trim().startsWith('[+:C')) {
        // extract uid
        var uidStart = curNode.nodeValue.indexOf('<')
        var uidEnd = curNode.nodeValue.indexOf('>')
        var uid = curNode.nodeValue.substring(uidStart + 1, uidEnd)

        // loop through the next siblings until we find the end comment
        let sibling = curNode.nextSibling
        while (sibling) {
          if (
            sibling.nodeType === 8 &&
            sibling.nodeValue.trim().startsWith(`[-:C<${uid}`)
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
    el.children = elChildren
    return el
  })
}

function getInsertionPoint(newBlock, uid) {
  var iterator = document.createNodeIterator(
    newBlock,
    NodeFilter.SHOW_TEXT,
    filterNone,
    false
  )
  var curNode

  while ((curNode = iterator.nextNode())) {
    if (curNode.nodeValue.trim().startsWith('[$ content $]')) {
      break
    }
  }
  return curNode
}

channel.on('update_block', function ({ uid, rendered_html, has_children }) {
  if (firstUpdate) {
    // insert styles to head
    var style = document.createElement('style')
    style.innerHTML = MOONWALK_OVERRIDE_STYLES
    document.head.appendChild(style)
  }

  var blockIndex = blockMap.findIndex((block) => block.uid === uid)
  if (blockIndex === -1) {
    // block not found —— rescan map
    buildMap()
    blockIndex = blockMap.findIndex((block) => block.uid === uid)
    if (blockIndex === -1) {
      console.error('Block not found')
    }
  }
  if (blockIndex >= 0) {
    var block = blockMap[blockIndex]
    if (rendered_html === '') {
      block.els.forEach((el) => el.element.remove())
      return
    }

    var doc = parser.parseFromString(rendered_html, 'text/html')
    var newBlocks = doc.querySelector('body').childNodes

    if (has_children) {
      var elsWithChildren = getChildren(block.els)
      block.els = elsWithChildren
    }

    // if current block has no elements, just insert the new
    // blocks and add them to the block.els array
    if (!block.els.length) {
      for (let idx = 0; idx < newBlocks.length; idx++) {
        if (
          newBlocks[idx].nodeType === 8 &&
          newBlocks[idx].nodeValue.trim().startsWith(`[-:B<${block.uid}`)
        ) {
          continue
        }

        var newElement = block.insertionPoint.parentNode.insertBefore(
          newBlocks[idx],
          block.insertionPoint
        )

        block.els[idx] = { element: newElement }
        forceLazyloadAllImages(newElement)
        forceLazyloadAllVideos(newElement)
      }
    } else {
      block.els.forEach((el, idx) => {
        if (has_children) {
          var childInsertionPoint = getInsertionPoint(newBlocks[idx], block.uid)
          if (childInsertionPoint) {
            // remove exitPoint from children array
            for (var i = 0; i < el.children.length; i++) {
              if (
                el.children[i].nodeType === 8 &&
                el.children[i].nodeValue.trim().startsWith(`[-:C<${block.uid}`)
              ) {
                continue
              }
              childInsertionPoint.parentNode.insertBefore(
                el.children[i],
                childInsertionPoint
              )
            }
            childInsertionPoint.remove()
          }

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

        el.element.remove()
        block.els[idx].element = newElement

        forceLazyloadAllImages(newElement)
        forceLazyloadAllVideos(newElement)
      })
    }
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
        if (
          a.dataset.src.split('?')[0] === b.dataset.src.split('?')[0] &&
          b.dataset.llLoaded
        ) {
          return false
        }

        // data-src differ. Update src
        b.src = b.dataset.src
      }

      return true
    },
    childrenOnly: true,
  })

  forceLazyloadAllImages()
  forceLazyloadAllVideos()

  buildMap()
})

channel.on('rerender', function (payload) {
  if (firstUpdate) {
    // insert styles to head
    var style = document.createElement('style')
    style.innerHTML = MOONWALK_OVERRIDE_STYLES
    document.head.appendChild(style)
  }
  document.documentElement.classList.add('is-updated-live-preview')
  var doc = parser.parseFromString(payload.html, 'text/html')
  var newBody = doc.querySelector('body')

  morphdom(body, newBody, {
    onBeforeElUpdated: (a, b) => {
      if (a.isEqualNode(b)) {
        return false
      }

      if (a.dataset.src && b.dataset.src) {
        if (
          a.dataset.src.split('?')[0] === b.dataset.src.split('?')[0] &&
          b.dataset.llLoaded
        ) {
          return false
        }

        // data-src differ. Update src
        b.src = b.dataset.src
      }

      return true
    },
    childrenOnly: false,
  })

  forceLazyloadAllImages()
  forceLazyloadAllVideos()

  buildMap()

  body.classList.remove('unloaded')
})
channel.join()
