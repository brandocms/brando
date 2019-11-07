export default function stripParams (params, toStrip) {
  for (let i = 0; i < toStrip.length; i++) {
    delete params[toStrip[i]]
  }
}
