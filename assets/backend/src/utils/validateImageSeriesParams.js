import stripParams from './stripParams'

export default function validateImageSeriesParams (params, imageParams) {
  for (let x = 0; x < imageParams.length; x++) {
    if (params.hasOwnProperty(imageParams[x]) && params[imageParams[x]].images.length) {
      for (let i = 0; i < params[imageParams[x]].images.length; i++) {
        if (!(params[imageParams[x]].images[i] instanceof File) && params[imageParams[x]].images[i] !== null) {
          stripParams(params[imageParams[x]].images[i], ['__typename', 'thumb', 'medium'])
          params[imageParams[x]].images[i] = JSON.stringify(params[imageParams[x]].images[i])
        }
      }
    }
  }
}
