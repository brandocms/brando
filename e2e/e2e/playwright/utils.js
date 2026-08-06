import { Locator, Page, expect } from '@playwright/test'
import Crypto from 'crypto'

const randomString = (size = 21) => Crypto.randomBytes(size).toString('base64').slice(0, size)

// a helper function to wait until the LV has no pending events
// timeout defaults to 15s to handle image uploads and other slow operations
const syncLV = async (page, timeout = 15000) => {
  const promises = [
    expect(page.locator('.phx-connected').first()).toBeVisible({ timeout }),
    expect(page.locator('.phx-change-loading')).toHaveCount(0, { timeout }),
    expect(page.locator('.phx-click-loading')).toHaveCount(0, { timeout }),
    expect(page.locator('.phx-submit-loading')).toHaveCount(0, { timeout }),
  ]
  return Promise.all(promises)
}

// The two client-side timers the block editor runs before it talks to the
// server. Both are plain `setTimeout`s in `assets/src/hooks/Block/index.js` with
// nothing observable to wait on, so a test cannot avoid sleeping past them —
// but it can sleep past *only* them and let `syncLV` cover everything after,
// which is the part that actually varies with machine speed. Keep these in step
// with the hook.
const BLOCK_DEBOUNCE_MS = 300 // phx-debounce on block inputs
const BLOCK_SHIP_SETTLE_MS = 400 // SHIP_SETTLE_MS — focusout → ship

// Wait until a block edit has been debounced, pushed, and answered.
//
// Replaces a flat `waitForTimeout(600)`. `syncLV` alone is not enough: while the
// debounce is still counting down nothing is in flight, so it returns
// immediately and the caller races the push.
const awaitBlockDebounce = async page => {
  await page.waitForTimeout(BLOCK_DEBOUNCE_MS + 50)
  await syncLV(page)
}

// Wait until a blur has shipped the block's ops to the other editors.
//
// Replaces flat 1200–1500ms sleeps. The receiving side is not covered here on
// purpose — assert it with a retrying `expect` on the *other* page, which is
// event-driven by construction and reports what was actually there when it gave
// up, instead of a sleep that says only "still not equal".
const awaitBlockShip = async page => {
  await page.waitForTimeout(BLOCK_SHIP_SETTLE_MS + 50)
  await syncLV(page)
}

// Cut the network under the browser, the way a lost connection does.
//
// Two steps, and both are needed:
//
//  1. `setOffline` stops new requests, so LiveSocket's reconnect attempts fail
//     for as long as we stay offline — the partition is real, not simulated by
//     asking the client to hold still.
//  2. An *established* websocket does not notice `setOffline` at all. It dies on
//     the next missed heartbeat, 30 seconds out, which is far too slow for a
//     spec. Closing the transport directly makes the drop land immediately.
//
// Step 2 is deliberately NOT `liveSocket.disconnect()`, which is the whole
// difference from the cooperative test: `disconnect()` is the client agreeing
// to stop, and it disarms auto-reconnect. Closing `conn` is the socket dying
// underneath LiveSocket with reconnection still armed — LiveSocket discovers
// the loss, fires `disconnected()` on every hook, and starts retrying into a
// network that is not there.
//
// The close code is load-bearing and used to be implicit. Phoenix arms the
// reconnect timer only when `closeCode !== 1000` (`socket.js:552`), and a bare
// `conn.close()` requests exactly 1000 — a clean, deliberate shutdown, which is
// the opposite of what this helper is for. It worked anyway only because step 1
// had already aborted the transport into a 1006 by the time `close()` ran, so
// the behaviour depended on the ordering of two lines rather than on anything
// stated. 4000 is in the private application range and is unambiguously not
// 1000, so reconnect is armed whether or not step 1 got there first.
const goOffline = async page => {
  await page.context().setOffline(true)
  await page.evaluate(() =>
    window.liveSocket.getSocket().conn.close(4000, 'e2e: simulated network loss')
  )
  await expect(page.locator('.phx-connected').first()).toBeHidden({ timeout: 15000 })
}

// Let the retries through. LiveSocket reconnects on its own schedule — nothing
// here tells it to, which is what makes the round trip a real one.
const goOnline = async page => {
  await page.context().setOffline(false)
  await syncLV(page, 30000)
}

// this function executes the given code inside the liveview that is responsible
// for the given selector; it uses private phoenix live view js functions, so it could
// break in the future
// we handle the evaluation in a LV hook
const evalLV = async (page, code, selector = '[data-phx-main]') =>
  await page.evaluate(
    ([code, selector]) => {
      return new Promise(resolve => {
        window.liveSocket.main.withinTargets(selector, (targetView, targetCtx) => {
          targetView.pushEvent(
            'event',
            document.body,
            targetCtx,
            'sandbox:eval',
            { value: code },
            {},
            ({ result }) => resolve(result)
          )
        })
      })
    },
    [code, selector]
  )

// executes the given code inside a new process
// (in context of a plug request)
const evalPlug = async (request, code) => {
  return await request
    .post('/eval', {
      data: { code },
    })
    .then(resp => resp.json())
}

const attributeMutations = (page, selector) => {
  // this is a bit of a hack, basically we create a MutationObserver on the page
  // that will record any changes to a selector until the promise is awaited
  //
  // we use a random id to store the resolve function in the window object
  const id = randomString(24)
  // this promise resolves to the mutation list
  const promise = page.locator(selector).evaluate((target, id) => {
    return new Promise(resolve => {
      const mutations = []
      let observer
      window[id] = () => {
        if (observer) observer.disconnect()
        resolve(mutations)
        delete window[id]
      }
      // https://developer.mozilla.org/en-US/docs/Web/API/MutationObserver
      observer = new MutationObserver((mutationsList, _observer) => {
        mutationsList.forEach(mutation => {
          if (mutation.type === 'attributes') {
            mutations.push({
              attr: mutation.attributeName,
              oldValue: mutation.oldValue,
              newValue: mutation.target.getAttribute(mutation.attributeName),
            })
          }
        })
      }).observe(target, { attributes: true, attributeOldValue: true })
    })
  }, id)

  return () => {
    // we want to stop observing!
    page.locator(selector).evaluate((_target, id) => window[id](), id)
    // return the result of the initial promise
    return promise
  }
}

export async function dragAndDrop(page, dragLocator, dropLocator, targetPosition) {
  const dragBoundingBox = await dragLocator.boundingBox()
  const dropBoundingBox = await dropLocator.boundingBox()

  // moving the mouse to the center of the drag HTML element
  await page.mouse.move(
    dragBoundingBox.x + dragBoundingBox.width / 2,
    dragBoundingBox.y + dragBoundingBox.height / 2
  )

  // activating the drag action
  await page.mouse.down()

  await page.waitForTimeout(100)

  // if targetPosition is undefined, defining the center of the
  // drop HTML element as the target position
  const targetX = targetPosition?.x || dropBoundingBox.x + dropBoundingBox.width / 2
  const targetY = targetPosition?.y || dropBoundingBox.y + dropBoundingBox.height / 2

  // moving the mouse to the (targetX, targetY) coordinates of the
  // drop element
  await page.mouse.move(targetX, targetY)
  await page.waitForTimeout(100)
  // releasing the mouse and terminating the drop option
  await page.mouse.up()
}

// Toggle live preview on/off - clicks the eye icon in form tab builtins
const toggleLivePreview = async page => {
  const btn = page.locator('.form-tab-builtins button.live-preview-toggle')
  await btn.scrollIntoViewIfNeeded()
  await btn.click()
  await syncLV(page)
}

// Get the preview iframe frame locator
const getPreviewFrame = page => {
  return page.frameLocator('.live-preview-wrapper iframe')
}

// Wait for preview to be ready after enabling
const waitForPreviewReady = async page => {
  await page.locator('.live-preview-wrapper iframe').waitFor({ state: 'visible', timeout: 30000 })

  // The iframe is visible well before the preview has rendered into it, so wait
  // for actual content rather than sleeping. The fixed 300ms this replaced was
  // tuned on a dev machine and ran out on a slower CI runner — after a
  // LiveSocket reconnect the iframe is recreated and re-rendered from scratch,
  // and the assertion that followed would find an empty document.
  await page
    .frameLocator('.live-preview-wrapper iframe')
    .locator('body *')
    .first()
    .waitFor({ state: 'attached', timeout: 30000 })
}

// Wait for preview update after making a change.
//
// `syncLV` only settles the parent LiveView, which is the side that *broadcasts*
// on the preview channel. The iframe then has to receive that over its own
// socket and morphdom it in, and this used to be covered by a flat 500ms sleep —
// the same bet on machine speed that made the reconnect test fail on CI.
//
// There is no completion signal to wait on: `channel.on('update')` sets
// `is-updated-live-preview` on the first update and never clears it, so it
// cannot distinguish one update from the next. Wait for the frame's DOM to go
// quiet instead — that covers morphdom regardless of how long the round trip
// takes, and returns as soon as it is done rather than always burning 500ms.
//
// Resolves rather than throws if nothing arrives, so a genuine failure surfaces
// as the caller's own assertion with its own message, not an opaque timeout here.
const waitForPreviewUpdate = async page => {
  await syncLV(page)

  await page
    .frameLocator('.live-preview-wrapper iframe')
    .locator('body')
    .evaluate(
      body =>
        new Promise(resolve => {
          const QUIET_MS = 250
          // The morph often lands while `syncLV` is still settling, i.e. before
          // this observer attaches, in which case there is nothing left to see.
          // Keep that path close to the 500ms this replaced rather than burning
          // a long timeout on every such call; when mutations *are* still
          // arriving the quiet timer extends the wait for as long as it needs.
          const FIRST_MUTATION_MS = 750

          let quietTimer = null
          const observer = new MutationObserver(() => {
            clearTimeout(quietTimer)
            clearTimeout(giveUp)
            quietTimer = setTimeout(finish, QUIET_MS)
          })

          const finish = () => {
            observer.disconnect()
            clearTimeout(quietTimer)
            clearTimeout(giveUp)
            resolve()
          }

          // Nothing morphed in: let the caller's assertion do the complaining.
          const giveUp = setTimeout(finish, FIRST_MUTATION_MS)

          observer.observe(body, {
            childList: true,
            subtree: true,
            attributes: true,
            characterData: true
          })
        }),
      undefined,
      { timeout: 30000 }
    )
}

// Click a device size button in live preview (desktop, tablet, mobile)
const setPreviewDevice = async (page, device) => {
  // Device buttons use data-live-preview-target attribute with values: desktop, tablet, mobile
  await page.locator(`.live-preview-wrapper button[data-live-preview-target="${device}"]`).click()
  await syncLV(page)
}

// Fill an input that has a slug field connected to it
// Uses pressSequentially to properly trigger the Slug hook's input event listener
const fillSlugSource = async (locator, text) => {
  await locator.click()
  await locator.pressSequentially(text, { delay: 10 })
  await locator.blur()
}

// Image uploads first open the asset browser so the user can confirm the
// destination folder. Keep upload specs aligned with that browser-first flow.
const confirmUploadFolder = async page => {
  const confirm = page.getByRole('button', { name: 'Upload here' })
  const opened = await confirm.waitFor({ state: 'visible', timeout: 3000 }).then(() => true).catch(() => false)
  if (!opened) return

  await confirm.click()
  await expect(confirm).not.toBeVisible({ timeout: 10000 })
}

module.exports = {
  randomString,
  syncLV,
  awaitBlockDebounce,
  awaitBlockShip,
  goOffline,
  goOnline,
  evalLV,
  evalPlug,
  attributeMutations,
  dragAndDrop,
  toggleLivePreview,
  getPreviewFrame,
  waitForPreviewReady,
  waitForPreviewUpdate,
  setPreviewDevice,
  fillSlugSource,
  confirmUploadFolder
}
