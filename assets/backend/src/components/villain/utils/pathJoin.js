export default function pathJoin (...args) {
  const str = args.map((part, i) => {
    if (i === 0) {
      return part.trim().replace(/[/]*$/g, '')
    } else {
      return part.trim().replace(/(^[/]*|[/]*$)/g, '')
    }
  }).filter(x => x.length).join('/')
  if (str[0] !== '/') {
    return '/' + str
  }
  return str
}
