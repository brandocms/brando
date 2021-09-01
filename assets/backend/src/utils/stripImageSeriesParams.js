import stripParams from './stripParams'

export default function stripImageSeriesParams (params) {
  delete params.imageSeries.cfg
  delete params.imageSeries.creator
  delete params.imageSeries.__typename

  for (let i = 0; i < params.imageSeries.images.length; i++) {
    if (!(params.imageSeries.images[i] instanceof File) && params.imageSeries.images[i] !== null) {
      stripParams(params.imageSeries.images[i], ['__typename', 'thumb', 'medium'])
      params.imageSeries.images[i] = JSON.stringify(params.imageSeries.images[i])
    }
  }
}
