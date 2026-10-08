// A change a widget holds back until its input settles (a debounce), that
// a save can ask for at once.
//
// `saveForm.js` dispatches `brando:flush` on the document before it reads
// the form: a widget whose JS holds a change back (the colour picker, a
// transformer's text fields) listens for it and calls `flush()`, so the
// change reaches the server ahead of the save instead of after it.
//
// Dependency free, so `test/javascript/pending_change.test.mjs` runs it in
// Node.

export const FLUSH_EVENT = 'brando:flush'

export default function pendingChange(fn, wait, timers = globalThis) {
  let timer = null
  let args = null

  const run = () => {
    timer = null
    const held = args
    args = null
    if (held) fn(...held)
  }

  const change = (...next) => {
    args = next
    timers.clearTimeout(timer)
    timer = timers.setTimeout(run, wait)
  }

  change.flush = () => {
    if (timer === null) return
    timers.clearTimeout(timer)
    run()
  }

  change.cancel = () => {
    timers.clearTimeout(timer)
    timer = null
    args = null
  }

  return change
}
