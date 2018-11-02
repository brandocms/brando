import ScrollReveal from 'scrollreveal'
const sr = ScrollReveal()

export function initializeMoonwalk () {
  let elements = document.querySelectorAll('[data-moonwalk-children]')
  Array.prototype.forEach.call(elements, function (el, i) {
    let children = el.children
    Array.prototype.forEach.call(children, function (c, x) {
      c.setAttribute('data-moonwalk', '')
    })
  })
}

export function moonwalkReady () {
  const revealOptions = {
    duration: 1200,
    distance: '20px',
    easing: 'ease',
    viewFactor: 0.0,
    delay: 50,
    interval: 120,
    useDelay: 'once'
  }

  const revealFadeOptions = {
    duration: 1200,
    distance: '0px',
    easing: 'ease',
    viewFactor: 0.0,
    delay: 50,
    interval: 120,
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
    sr.reveal(walks, revealOptions, 150)

    walks = walkSections[i].querySelectorAll('[data-moonwalk-fade]')
    sr.reveal(walks, revealFadeOptions, 150)
  }

  sr.reveal('[data-moonwalk-offset]', offsetRevealOptions, 150)
}
