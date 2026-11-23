// Uploads handed over by a multi block's media drop (`MediaDrop`) to the
// field of the entry it made for the file, by the upload's ref: the upload
// manager's, or a provider hook's (`providerVideoUploader`). When that
// upload settles, the block field holding the entry is told
// (`brando:handed-upload-settled` on the `BlockField` hook's element), not
// the entry's field: an entry moved to another block is off the page
// between the patch that takes it away and the one that puts it back.
// Another file dropped on the field meanwhile is the field's own and
// settles nothing.
const handovers = new Map()

export function handOver(ref, handover) {
  handovers.set(ref, handover)
}

// The upload's state as its owner reports it: processing or done is the
// entry's file, an error or a cancel is not, and so is a done carrying an
// error (a provider upload the server could not complete). `aborted`: the
// upload stopped when its provider hook was taken off the page.
export function settleUpload(ref, { status, error, aborted }) {
  const handover = handovers.get(ref)
  if (!handover || !['processing', 'done', 'error', 'cancelled'].includes(status)) return

  handovers.delete(ref)
  const failed = status === 'error' || status === 'cancelled' || !!error
  settle(handover, { failed, error: status === 'cancelled' ? null : error || null, aborted: !!aborted })
}

// Also for a handed-over file the field refuses before an upload starts
export function settle({ uid, token, blockField }, { failed, error = null, aborted = false }) {
  document.getElementById(blockField)?.dispatchEvent(new CustomEvent('brando:handed-upload-settled', {
    detail: { uid, token, failed, error, aborted },
  }))
}
