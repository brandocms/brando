import { alerts } from '../../../utils/alerts'

export default async function storeTemplateSequence (sequence, extraHeaders, url, toast) {
  const headers = new Headers()
  headers.append('accept', 'application/json, text/javascript, */*; q=0.01')

  if (extraHeaders) {
    for (const key of Object.keys(extraHeaders)) {
      headers.append(key, extraHeaders[key])
    }
  }

  const formData = new FormData()
  formData.append('sequence', JSON.stringify(sequence))
  const request = new Request(url, { headers, method: 'post', body: formData })

  try {
    const response = await fetch(request)
    const data = await response.json()

    if (data.status === 200) {
      toast.success({ message: 'Rekkefølgen ble lagret' })
      return data
    }
  } catch (e) {
    alerts.alertError('Feil', 'Feil ved lagring av rekkefølge i database.')
    console.error(e)
  }
}
