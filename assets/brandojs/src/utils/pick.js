export default function pick (o, ...props) {
  return Object.assign({}, ...props.map(prop => {
    if (o.hasOwnProperty(prop)) return { [prop]: o[prop] }
  }))
}
