// A projection of the sticky manager's state. It never owns files or transfers.
const records = new Map()
const listeners = new Map()
const latest = new Map()
let sequence = 0
const terminal = status => ['done', 'error', 'cancelled'].includes(status)

export const uploadTargetKey = (target) => JSON.stringify([
  target.deliver_topic || '', target.kind || '', target.kind?.startsWith('entry_field') ? '' : target.component_id || '',
  target.var_key || '', target.field || '', target.path || [], target.kind?.endsWith('_gallery') ? 'gallery' : target.asset_type || '',
])

const currentRecords = key => Array.from(records.values()).filter(record => record.key === key && record.batch === latest.get(key))

const currentState = (key) => {
  const items = currentRecords(key)
  if (!items.length) return null
  if (!items[0].collection || items.length === 1) return items[0]
  const active = items.filter(item => !terminal(item.status))
  const failed = items.filter(item => item.status === 'error')
  const completed = items.filter(item => item.status === 'done').length
  const status = active.some(item => item.status === 'uploading') ? 'uploading' :
    active.some(item => item.status === 'processing') ? 'processing' :
      active.length ? 'queued' : failed.length ? 'error' :
        items.some(item => item.status === 'cancelled') ? 'cancelled' : 'done'
  return {
    status, total: items.length, completed, failed: failed.length,
    progress: Math.round(items.reduce((sum, item) => sum + (['processing', 'done'].includes(item.status) ? 100 : item.progress || 0), 0) / items.length),
    error: failed.length ? `${failed.length} of ${items.length} uploads failed. ${failed[0].error}` : null,
  }
}

const notify = (key) => listeners.get(key)?.forEach(listener => listener(currentState(key)))

export function trackUpload(ref, target, attrs = {}) {
  const key = uploadTargetKey(target)
  const collection = target.kind?.endsWith('_gallery')
  const batch = collection && currentRecords(key).some(item => !terminal(item.status)) ? latest.get(key) : ++sequence
  const record = { ref, key, batch, collection, status: 'queued', progress: 0, ...attrs }
  records.set(ref, record)
  latest.set(key, batch)
  notify(key)
  expire(record)
}

export function updateUpload(ref, attrs) {
  const record = records.get(ref)
  if (!record) return
  Object.assign(record, attrs)
  notify(record.key)
  expire(record)
}

function expire(record) {
  if (terminal(record.status) && !record.expiring) {
    record.expiring = true
    setTimeout(() => {
      if (records.get(record.ref) !== record) return
      // Keep the complete batch visible until its final transfer has settled.
      if (record.collection && currentRecords(record.key).some(item => !terminal(item.status))) {
        record.expiring = false
        expire(record)
        return
      }
      records.delete(record.ref)
      if (!Array.from(records.values()).some(item => item.key === record.key)) latest.delete(record.key)
      notify(record.key)
    }, 120000)
  }
}

export function subscribeToUpload(target, listener) {
  const key = uploadTargetKey(target)
  if (!listeners.has(key)) listeners.set(key, new Set())
  listeners.get(key).add(listener)
  listener(currentState(key))
  return () => {
    listeners.get(key)?.delete(listener)
    if (!listeners.get(key)?.size) listeners.delete(key)
  }
}
