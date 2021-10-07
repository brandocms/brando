export default function mapMultiSelects (params, arrParams) {
  for (let i = 0; i < arrParams.length; i++) {
    if (!Object.prototype.hasOwnProperty.call(params, arrParams[i])) {
      continue
    }
    params[arrParams[i]] = params[arrParams[i]].map(a => {
      if (typeof a === 'object') {
        return a.id
      } else {
        return a
      }
    })
  }
}
