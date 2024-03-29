/* Add live preview class to html */
document.documentElement.classList.add('is-live-preview');
var token = document.querySelector('meta[name="user_token"]').getAttribute('content');
var previewSocket = new Phoenix.Socket('/admin/socket', { params: { token: token } });
var main = document.querySelector('main')
var parser = new DOMParser();
previewSocket.connect();
var channel = previewSocket.channel("live_preview:" + livePreviewKey)

function forceLazyloadAllImages () {
  document.querySelectorAll('[data-ll-image]:not([data-ll-loaded]), [data-ll-srcset-image]:not([data-ll-loaded])').forEach(llImage => {
    llImage.src = llImage.dataset.src;
    if (llImage.dataset.srcset) {
      llImage.srcset = llImage.dataset.srcset;
    }
    llImage.src = llImage.dataset.src;
    llImage.dataset.llLoaded = '';
  })
}

function forceLazyloadAllVideos () {
  document.querySelectorAll('[data-smart-video] video:not([data-booted])').forEach(llVideo => {
    llVideo.src = llVideo.dataset.src;
    llVideo.dataset.booted = '';
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

  forceLazyloadAllImages();
  forceLazyloadAllVideos();
});
channel.join();
