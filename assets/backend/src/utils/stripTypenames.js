export default function stripTypenames (params, stripProps) {
  for (let i = 0; i < stripProps.length; i++) {
    if (!Object.prototype.hasOwnProperty.call(params, stripProps[i])) {
      continue
    }
    params[stripProps[i]] = strip(params[stripProps[i]])
  }
}

function strip (value) {
  if (value === null || value === undefined) {
    return value
  } else if (Array.isArray(value)) {
    return value.map(v => strip(v))
  } else if (typeof value === 'object') {
    const newObj = {}
    Object.entries(value).forEach(([key, v]) => {
      if (key !== '__typename') {
        newObj[key] = strip(v)
      }
    })
    return newObj
  }
  return value
}
