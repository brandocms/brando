import stripParams from './stripParams'

export default function validateImageParams (params, imageParams) {
  for (let i = 0; i < imageParams.length; i++) {
    if (!(params[imageParams[i]] instanceof File) && params[imageParams[i]] !== null) {
      stripParams(params[imageParams[i]], ['__typename', 'thumb'])
      params[imageParams[i]] = JSON.stringify(params[imageParams[i]])
    }
  }
}
