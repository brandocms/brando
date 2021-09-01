/**
 * DEPRECATE THIS SOME TIME.
 * @param {*} value
 */
export default function removeTypename (value) {
  if (value === null || value === undefined) {
    return value
  } else if (Array.isArray(value)) {
    value = value.map(v => removeTypename(v))
    return value
  } else if (typeof value === 'object') {
    const newObj = {}
    Object.entries(value).forEach(([key, v]) => {
      if (key !== '__typename') {
        newObj[key] = removeTypename(v)
      }
    })
    value = newObj
    return value
  }
  return value
}
