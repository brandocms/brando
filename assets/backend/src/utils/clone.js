export default function clone (obj) {
  if (obj == null || typeof (obj) !== 'object') {
    return obj
  }

  const temp = obj.constructor()

  for (const key in obj) {
    temp[key] = clone(obj[key])
  }

  return temp
}
