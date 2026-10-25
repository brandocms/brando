import { animate as motionAnimate, stagger } from '@brandocms/jupiter'

// The admin's timings were tuned against GSAP's curves, and Motion's own
// `easeOut` is flatter than any of them. These are the same curves as
// cubic-beziers, named after the GSAP eases they replace.
export const ease = {
  none: 'linear',
  sineOut: [0.39, 0.575, 0.565, 1],
  sineInOut: [0.445, 0.05, 0.55, 0.95],
  power2Out: [0.215, 0.61, 0.355, 1],
  power2InOut: [0.645, 0.045, 0.355, 1],
  power3Out: [0.165, 0.84, 0.44, 1],
  circIn: 'circIn',
  circOut: 'circOut',
}

// Honour both the admin preference and the OS setting, including changes made
// while the editor is open. E2E runs (`data-env="e2e"` on the body) move
// nothing either, as the E2E stylesheet does for CSS motion, unless the body
// has `data-real-motion="true"` (`config :brando, :e2e_real_motion`, or a test
// opting in).
export const prefersReducedMotion = () =>
  document.querySelector('meta[name="prefers_reduced_motion"]')?.content === 'true' ||
  window.matchMedia('(prefers-reduced-motion: reduce)').matches ||
  (document.body?.dataset.env === 'e2e' && document.body.dataset.realMotion !== 'true')

// The consumer's CSS optimiser can turn 350ms into .35s, including inside
// custom properties. Web Animations and timers always expect milliseconds.
export const motionDuration = (el, property) => {
  const value = getComputedStyle(el).getPropertyValue(property).trim()
  return (parseFloat(value) || 0) * (value.endsWith('ms') ? 1 : 1000)
}

// With reduced motion, every animation jumps straight to its end state but
// still resolves `finished`, so completion handlers run as usual.
const withMotionPreference = (options = {}) =>
  prefersReducedMotion() ? { ...options, skipAnimations: true } : options

// Unless told otherwise, GSAP eased with Jupiter's `sine.out` default.
export function animate(subject, keyframes, options) {
  return motionAnimate(subject, keyframes, withMotionPreference({ ease: ease.sineOut, ...options }))
}

export function sequence(segments, options) {
  return motionAnimate(segments, withMotionPreference(options))
}

// Applies styles at once, before the next paint. Motion only writes on its
// next frame, which is too late when an element must be hidden before a rule
// that hides it is lifted. Later animations of these properties must name
// their starting keyframe: Motion does not see values written here.
export function set(targets, styles) {
  const elements = targets instanceof Element ? [targets] : Array.from(targets || [])
  elements.forEach(el => el && Object.assign(el.style, styles))
}

// Keeps a hook's running animations, so `destroyed()` can stop them rather
// than leave them driving detached elements.
export function animationTracker() {
  const running = new Set()

  return {
    track(animation) {
      running.add(animation)
      animation.finished.then(() => running.delete(animation))
      return animation
    },

    stopAll() {
      running.forEach(animation => animation.stop())
      running.clear()
    },
  }
}

export { stagger }
