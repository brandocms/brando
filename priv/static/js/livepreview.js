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
      for (var i = 0; i < images.length; i++) {
        images[i].src = images[i].getAttribute('data-src');
      }
    }
  }
}

channel.on('update', function (payload) {
  var doc = parser.parseFromString(payload.html, "text/html");
  var newMain = doc.querySelector('main');
  morphdom(main, newMain, {
    onBeforeElUpdated: (a, b) => {
      if (a.isEqualNode(b)) {
        return false;
      }

      if (a.dataset.src && b.dataset.src) {
        if (a.dataset.src === b.dataset.src) {
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
