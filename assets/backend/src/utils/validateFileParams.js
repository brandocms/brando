export default function validateFileParams (params, fileParams) {
  for (let i = 0; i < fileParams.length; i++) {
    if (!Object.prototype.hasOwnProperty.call(params, fileParams[i])) {
      continue
    }
    if (!(params[fileParams[i]] instanceof File) && params[fileParams[i]] !== null) {
      delete params[fileParams[i]]
    }
  }
}
