export default function hookLightbox () {
  $('a[data-lightbox]').on('click', function(e) {
    e.preventDefault()
    fader.style.display = 'block'
    Velocity(
      fader,
      {
        opacity: 1
      },
      {
        duration: 250,
        complete: function(elements) {
          let box = $(`
            <div class="lightbox-backdrop">
              <img class="lightbox-image img-fluid m-lg" src="${e.currentTarget.href}">
            </div>
          `)
          box.appendTo('body')
          imagesLoaded(box[0], function(instance) {
            Velocity(
              box[0],
              {
                opacity: 1
              },
              {
                duration: 500,
                complete: function(elements) {
                  fader.style.display = 'none'
                  fader.style.opacity = 0
                }
              }
            )
          })
          box.on('click', function(e) {
            Velocity(
              box[0],
              {
                opacity: 0
              },
              {
                duration: 500,
                complete: function() {
                  box.remove()
                }
              }
            )
          })
        }
      }
    )

  })
}
