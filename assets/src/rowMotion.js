import { motionDuration, prefersReducedMotion } from './motion'

export default function revealRow(row, removing = false) {
  if (prefersReducedMotion() || !row.getBoundingClientRect().height) return
  const style = getComputedStyle(row)
  const duration = motionDuration(row, removing ? '--motion-leave' : '--motion-enter')
  const options = { duration, easing: style.getPropertyValue('--motion-ease').trim(), ...(removing ? { fill: 'forwards' } : {}) }
  // Reverse the frames, not playback: reversing playback also reverses the
  // ease-out, making removal hesitate before suddenly collapsing at the end.
  const play = frames => row.animate(removing ? frames.reverse() : frames, options)
  // A table row cannot shrink below the intrinsic height of its cells. Reveal
  // its contents without changing column widths or the table's display model.
  if (style.display === 'table-row') {
    return play([
      { opacity: 0, clipPath: 'inset(-12px -2px 100% -2px)' },
      { opacity: 1, clipPath: 'inset(-12px -2px 0 -2px)' },
    ])
  }
  const end = { height: `${row.getBoundingClientRect().height}px`, opacity: 1 }
  const start = { height: '0px', opacity: 0 }
  for (const property of ['paddingTop', 'paddingBottom', 'marginTop', 'marginBottom', 'borderTopWidth', 'borderBottomWidth']) {
    start[property] = '0px'
    end[property] = style[property]
  }
  return play([
    // The insert control straddles the top edge; include that overhang while
    // revealing the row's contents from the bottom edge of its growing box.
    { ...start, clipPath: 'inset(-12px -2px 0 -2px)', minHeight: 0 },
    { ...end, clipPath: 'inset(-12px -2px 0 -2px)', minHeight: 0 },
  ])
}
