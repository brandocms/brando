
export default function serializeParams (entry, serializeProperties) {
  for (let i = 0; i < serializeProperties.length; i++) {
    if (!Object.prototype.hasOwnProperty.call(entry, serializeProperties[i])) {
      continue
    }
    if (Array.isArray(entry[serializeProperties[i]])) {
      entry[serializeProperties[i]] = JSON.stringify(entry[serializeProperties[i]])
    }
  }
}
