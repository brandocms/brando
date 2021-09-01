import { alerts } from '../../../utils/alerts'

export default async function storeTemplate (template, extraHeaders, url, toast) {
  const headers = new Headers()
  headers.append('accept', 'application/json, text/javascript, */*; q=0.01')

  if (extraHeaders) {
    for (const key of Object.keys(extraHeaders)) {
      headers.append(key, extraHeaders[key])
    }
  }

  const formData = new FormData()
  formData.append('template', JSON.stringify(template))
  const request = new Request(url, { headers, method: 'post', body: formData })

  try {
    const response = await fetch(request)
    const data = await response.json()

    if (data.status === 200) {
      toast.success({ message: 'Malen ble lagret' })
      return data
    }
  } catch (e) {
    alerts.alertError('Feil', 'Feil ved lagring av mal i database.')
    console.error(e)
  }
}
