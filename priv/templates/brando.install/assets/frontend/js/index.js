/**
 * APPLICATION FRONTEND
 * (c) 2018
 */

import $ from 'jquery'
import ScrollReveal from 'scrollreveal'
window.sr = ScrollReveal()
console.log(sr)
import Headroom from 'headroom.js'
import imagesLoaded from 'imagesloaded'
import Velocity from 'velocity-animate'
import '../css/app.scss'

const SLIDE_DURATION = 4000

$(() => {
  if(window.location.hash) {
    $('header').addClass("headroom--unpinned")
  }

  $('a:not([href*="#"])')
    .click(function(e) {
      // hide the loader
      $('.loading-container').hide()
      const that = this
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
            window.location = $(that).attr('href')
          }
        }
      )
    })

  $('[data-moonwalk-children]').each(function(idx, m) {
    const $children = $(m).children()
    $children.each(function(idx, c) {
      $(c).attr('data-moonwalk', '')
    })
  })

  $('.hamburger').click(function () {
    $(this).toggleClass('is-active')
    $('body').toggleClass('open-menu')
  })

  var opts = {
    offset: 0,
    tolerance: {
      down: 5,
      up: 10
    },
    classes: {
      initial: "animated"
    }
  };

  var headroom  = new Headroom(document.querySelector('header'), opts);
  headroom.init()

  imagesLoaded(document.querySelector('body'), function(instance) {
    setTimeout(setReady, 500)
  })
})

function setReady () {
  $('body').removeClass('unloaded')
  const fader = document.querySelector('#fader')

  const revealOptions = {
    duration: 1200,
    distance: '20px',
    easing: 'ease',
    viewFactor: 0.0,
    delay: 0,
    useDelay: 'once'
  }

  const offsetRevealOptions = {
    duration: 1200,
    distance: '20px',
    easing: 'ease',
    viewFactor: 0.0,
    viewOffset: { top: 0, right: 0, bottom: -400, left: 0 },
    delay: 500,
    useDelay: 'once'
  }

  const walkSections = document.querySelectorAll('[data-moonwalk-section]')

  // loop through walk sections
  for (let i = 0; i < walkSections.length; i++) {
    // process walksection
    let walks = walkSections[i].querySelectorAll('[data-moonwalk]')
    sr.reveal(walks, revealOptions, 150);
  }

  // sr.reveal('[data-moonwalk]', revealOptions, 150);
  sr.reveal('[data-moonwalk-offset]', offsetRevealOptions, 150);

  Velocity(
    fader,
    {
      opacity: 0
    },
    {
      duration: 1000,
      complete: function(elements) {
        fader.style.display = 'none'
      }
    }
  )
}

let App = {};


export default App;
