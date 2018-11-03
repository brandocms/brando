import imagesLoaded from 'imagesloaded'
import { TweenLite } from 'gsap/TweenMax'

export function initializeLightbox () {
  const lightboxes = document.querySelectorAll('a[data-lightbox]')
  const fader = document.querySelector('#fader')

  lightboxes.forEach(lightbox => {
    lightbox.addEventListener('click', function (e) {
      e.preventDefault()
      const href = this.href
      fader.style.display = 'block'

      TweenLite.to(fader, 0.250, {
        opacity: 1,
        onComplete: () => {
          const wrapper = document.createElement('div')
          const img = document.createElement('img')
          wrapper.classList.add('lightbox-backdrop')
          img.classList.add('lightbox-image', 'img-fluid', 'm-lg')
          img.src = href

          wrapper.appendChild(img)
          document.body.appendChild(wrapper)

          imagesLoaded(wrapper, function (instance) {
            TweenLite.to(wrapper, 0.5, {
              opacity: 1,
              onComplete: () => {
                fader.style.display = 'none'
                fader.style.opacity = 0
              }
            })
          })

          wrapper.addEventListener('click', e => {
            TweenLite.to(wrapper, 0.5, {
              opacity: 0,
              onComplete: () => {
                wrapper.parentNode.removeChild(wrapper)
              }
            })
          })
        }
      })
    })
  })
}
