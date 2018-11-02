import imagesLoaded from 'imagesloaded'
import Velocity from 'velocity-animate'

export function initializeLightbox() {
  const lightboxes = document.querySelectorAll('a[data-lightbox]')
  const fader = document.querySelector('#fader')

  lightboxes.forEach(lightbox => {
    lightbox.addEventListener('click', function (e) {
      e.preventDefault()
      const href = this.href
      fader.style.display = 'block'

      Velocity(
        fader,
        {
          opacity: 1
        },
        {
          duration: 250,
          complete: () => {
            const wrapper = document.createElement('div')
            const img = document.createElement('img')
            wrapper.classList.add('lightbox-backdrop')
            img.classList.add('lightbox-image', 'img-fluid', 'm-lg')
            img.src = href

            wrapper.appendChild(img)
            document.body.appendChild(wrapper)

            imagesLoaded(wrapper, function (instance) {
              Velocity(
                wrapper,
                {
                  opacity: 1
                },
                {
                  duration: 500,
                  complete: () => {
                    fader.style.display = 'none'
                    fader.style.opacity = 0
                  }
                }
              )
            })
            wrapper.addEventListener('click', e => {
              Velocity(
                wrapper,
                {
                  opacity: 0
                },
                {
                  duration: 500,
                  complete: () => {
                    wrapper.parentNode.removeChild(wrapper)
                  }
                }
              )
            })
          }
        }
      )
    })
  })
}
