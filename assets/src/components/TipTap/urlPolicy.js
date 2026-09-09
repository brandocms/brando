const protocols = new Set(['http', 'https', 'ftp', 'ftps', 'mailto', 'tel', 'callto', 'sms', 'cid', 'xmpp'])
export function isAllowedUri(value) {
  if (typeof value !== 'string' || !value || /[\u0000-\u0020\u007f-\u009f\u00a0\u1680\u180e\u2000-\u202f\u205f\u3000\\]/u.test(value)) return false
  const scheme = value.match(/^([a-z][a-z0-9+.-]*):/i)
  return !scheme || protocols.has(scheme[1].toLowerCase())
}
export function normalizeUrl(value) {
  let url = String(value ?? '').trim()
  // Only bare hostnames, not paths or arbitrary words, acquire a protocol.
  if (/^(?:[a-z0-9-]+\.)+[a-z]{2,}(?::\d+)?(?:[/?#]|$)/i.test(url)) url = `https://${url}`
  return isAllowedUri(url) ? url : null
}
export function linkRel(target, rel = '') {
  const values = new Set(String(rel || '').split(/\s+/).filter(Boolean))
  if (target === '_blank') { values.add('noopener'); values.add('noreferrer') }
  return [...values].join(' ') || null
}
