/**
 * Brando live preview: storage for a sandboxed page.
 *
 * Preview pages and shared preview snapshots are served with a CSP `sandbox`
 * (`Brando.Plug.LivePreview.sandbox_policy/0`), so their origin is opaque and
 * reading `localStorage`, `sessionStorage` or `document.cookie` throws. The
 * site's own scripts run in the preview and may read them as they start, so
 * this script, first in `<head>`, puts stand-ins in their place that keep
 * what is written in memory for the life of the page. On a page where they
 * work, it changes nothing.
 */
;(function () {
  function memoryStorage() {
    var items = new Map()
    var storage = {
      getItem: function (key) {
        key = String(key)
        return items.has(key) ? items.get(key) : null
      },
      setItem: function (key, value) {
        items.set(String(key), String(value))
      },
      removeItem: function (key) {
        items.delete(String(key))
      },
      clear: function () {
        items.clear()
      },
      key: function (index) {
        var keys = Array.from(items.keys())
        return index >= 0 && index < keys.length ? keys[index] : null
      },
    }
    Object.defineProperty(storage, 'length', {
      get: function () {
        return items.size
      },
    })
    return storage
  }

  ;['localStorage', 'sessionStorage'].forEach(function (name) {
    try {
      window[name]
    } catch (_) {
      try {
        Object.defineProperty(window, name, { value: memoryStorage(), configurable: true })
      } catch (_) {}
    }
  })

  try {
    document.cookie
  } catch (_) {
    var jar = new Map()

    // `name=value; attribute; …`: an expired cookie (`max-age` of 0 or less,
    // or `expires` in the past) is how scripts delete one.
    var write = function (cookie) {
      var parts = String(cookie).split(';')
      var pair = parts.shift()
      var at = pair.indexOf('=')
      var name = (at < 0 ? '' : pair.slice(0, at)).trim()
      var value = (at < 0 ? pair : pair.slice(at + 1)).trim()
      var expired = parts.some(function (part) {
        var attribute = part.split('=')
        var key = attribute[0].trim().toLowerCase()
        var setting = attribute.slice(1).join('=').trim()
        if (key === 'max-age') return Number(setting) <= 0
        if (key === 'expires') return Date.parse(setting) <= Date.now()
        return false
      })
      if (expired) jar.delete(name)
      else jar.set(name, value)
    }

    try {
      Object.defineProperty(document, 'cookie', {
        configurable: true,
        get: function () {
          return Array.from(jar, function (entry) {
            return entry[0] ? entry[0] + '=' + entry[1] : entry[1]
          }).join('; ')
        },
        set: write,
      })
    } catch (_) {}
  }
})()
