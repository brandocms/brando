import stripParams from './stripParams'

export default function validateImageParams (params, imageParams) {
  // add metaImage
  imageParams.push('metaImage')

  for (let i = 0; i < imageParams.length; i++) {
    if (!Object.prototype.hasOwnProperty.call(params, imageParams[i])) {
      continue
    }
    if (!(params[imageParams[i]] instanceof File) && params[imageParams[i]] !== null) {
      console.log(params[imageParams[i]])
      params[imageParams[i]] = stripParams(params[imageParams[i]], [
        '__typename',
        'base64',
        'credits',
        'path',
        'sizes',
        'thumb',
        'small',
        'medium',
        'large',
        'xlarge',
        'original'])
    }
  }
}
