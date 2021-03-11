/* Add live preview class to html */
document.documentElement.classList.add('is-live-preview');
var token = localStorage.getItem('token');
var previewSocket = new Phoenix.Socket('/admin/socket', { params: { guardian_token: token } });
var main = document.querySelector('main')
var parser = new DOMParser();
previewSocket.connect();
var channel = previewSocket.channel("live_preview:" + livePreviewKey)

function forceLazyload(node) {
  if (node.tagName === "IMG" && node.getAttribute('data-ll-image')) {
    node.src = node.getAttribute('data-src');
  } else {
    if (node.querySelectorAll) {
      var images = node.querySelectorAll('img[data-ll-image]:not([data-ll-loaded])')
      var srcsetImages = node.querySelectorAll('img[data-ll-srcset-image]:not([data-ll-loaded])')
      for (var i = 0; i < images.length; i++) {
        images[i].src = images[i].getAttribute('data-src');
        images[i].dataset.llLoaded = ''
      }
      for (var i = 0; i < srcsetImages.length; i++) {
        srcsetImages[i].src = srcsetImages[i].getAttribute('data-src');
        srcsetImages[i].dataset.llLoaded = ''
      }
    }
  }
}

channel.on('update', function (payload) {
  document.documentElement.classList.add('is-updated-live-preview')
  var doc = parser.parseFromString(payload.html, "text/html");
  var newMain = doc.querySelector('main');
  morphdom(main, newMain, {
    onBeforeElUpdated: (a, b) => {
      if (a.isEqualNode(b)) {
        return false;
      }

      if (a.dataset.src && b.dataset.src) {
        if (a.dataset.src.split('?')[0] === b.dataset.src.split('?')[0]) {
          return false;
        }

        // data-src differ. Update src
        b.src = b.dataset.src;
      }
      return true;
    },

    onElUpdated: (node) => {
      forceLazyload(node);
      return node;
    },

    onBeforeNodeAdded: (node) => {
      forceLazyload(node);
      return node;
    },

    childrenOnly: true
  });
});
channel.join();
