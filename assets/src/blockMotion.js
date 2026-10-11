import { motionDuration, prefersReducedMotion } from './motion'

// Keep the expanded contents painted while their own frame closes. Hiding
// them first only animates empty space, especially in a tall module.
export default function blockMotion(liveSocket) {
  const running = new WeakMap()
  const js = liveSocket.js()
  return (block, collapsed) => {
    const frame = block.querySelector(':scope > .block')
    if (!frame) return
    const height = frame.getBoundingClientRect().height
    running.get(block)?.cancel()
    js.removeAttribute(block, 'data-block-motion')
    block.classList.toggle('collapsed', collapsed)
    const nextHeight = frame.getBoundingClientRect().height
    if (prefersReducedMotion() || Math.abs(height - nextHeight) < 1) return

    // Sticky for just the animation: a validation patch may arrive halfway
    // through, and must not hide the children until the frame has closed.
    js.setAttribute(block, 'data-block-motion', 'true')
    const animation = frame.animate([
      { height: `${height}px`, minHeight: 0, overflow: 'clip' },
      { height: `${nextHeight}px`, minHeight: 0, overflow: 'clip' },
    ], {
      duration: motionDuration(frame, collapsed ? '--motion-leave' : '--motion-enter'),
      easing: getComputedStyle(frame).getPropertyValue('--motion-ease').trim(),
      fill: 'both',
    })
    running.set(block, animation)
    animation.finished.then(() => {
      if (running.get(block) !== animation) return
      js.removeAttribute(block, 'data-block-motion')
      running.delete(block)
      animation.cancel()
    }).catch(() => {}) // Reversals start from the current painted height.
  }
}
