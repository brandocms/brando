export default function mapMultiSelect (arr) {
  return arr.map(a => {
    if (typeof a === 'object') {
      return a.id
    } else {
      return a
    }
  })
}
