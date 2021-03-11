/* Add live preview class to html */
document.documentElement.classList.add('is-live-preview');
var token = localStorage.getItem('token');
var previewSocket = new Phoenix.Socket('/admin/socket', { params: { guardian_token: token } });
var main = document.querySelector('main')
var parser = new DOMParser();
previewSocket.connect();
var channel = previewSocket.channel("live_preview:" + livePreviewKey)

function forceLazyloadAll () {
  document.querySelectorAll('[data-ll-image]:not([data-ll-loaded]), [data-ll-srcset-image]:not([data-ll-loaded])').forEach(llImage => {
    llImage.src = llImage.dataset.src;
    if (llImage.dataset.srcset) {
      llImage.srcset = llImage.dataset.srcset;
    }
    llImage.src = llImage.dataset.src;
    llImage.dataset.llLoaded = '';
  })
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
        if ((a.dataset.src.split('?')[0] === b.dataset.src.split('?')[0]) && b.dataset.llLoaded) {
          return false;
        }

        // data-src differ. Update src
        b.src = b.dataset.src;
      }

      return true;
    },
    childrenOnly: true
  });

  forceLazyloadAll()
});
channel.join();
