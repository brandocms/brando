// Authoring capabilities are distinct from the schema used to preserve old HTML.
import registry from './capabilities.json' with { type: 'json' }
export const defaultCapabilities = registry.default
export const presets = registry.presets
export function resolveCapabilities(value) {
  if (value == null || value === 'all') return [...defaultCapabilities]
  const values = Array.isArray(value) ? value : String(value).split('|').filter(Boolean)
  return [...new Set(values.flatMap(key => key === 'all' || key == null ? defaultCapabilities : key === 'action_button' ? ['button'] : [key]))]
}
export function addPreset(value, preset) {
  return [...new Set([...resolveCapabilities(value), ...(presets[preset] || [])])]
}
export const headingLevelForElement = element => /^h[1-6]$/.test(element) ? Number(element[1]) : null
// Exact code points, including punctuation and case. Never serialized into HTML.
export const markNameForStyle = (element, className) => 'style_' + Array.from(`${element}:${className}`, c => c.codePointAt(0).toString(16)).join('_')
export function normalizeStyles(value) {
  if (typeof value === 'string') { try { value = JSON.parse(value) } catch { return [] } }
  if (!Array.isArray(value)) return []
  const seen = new Set()
  return value.flatMap(style => {
    const element = String(style?.element || '').trim().toLowerCase()
    const className = String(style?.class || '').trim()
    const key = `${element}:${className}`
    if (!/^(p|h[1-6]|span)$/.test(element) || !/^[A-Za-z_][A-Za-z0-9_-]*$/.test(className) || seen.has(key)) return []
    seen.add(key)
    return [{ key, element, className, mode: element === 'span' ? 'mark' : 'node', markName: markNameForStyle(element, className), label: String(style.label || `${element.toUpperCase()} ${className}`), icon: style.icon || null }]
  })
}
