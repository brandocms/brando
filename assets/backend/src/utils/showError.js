import { alerts } from './alerts'
import nprogress from 'nprogress'

export default function showError (err) {
  if (err.graphQLErrors && err.graphQLErrors.length) {
    const msgs = err.graphQLErrors.map(e => {
      if (e.changeset) {
        const csErrors = []
        for (const [key, value] of Object.entries(e.changeset.errors)) {
          csErrors.push(`<strong>${key}</strong>: ${value}`)
        }

        return `
          ${e.path.join(' / ')}<br><br>
          ${csErrors.join('<br>')}
        `
      } else {
        return e.message
      }
    })
    alerts.alertError('Feil', msgs)
    console.error(err)
  } else if (err.error) {
    alerts.alertError('Feil', err.error)
    console.error(err)
  } else {
    alerts.alertError('Ukjent feil', err.message)
    console.error(err)
  }
  nprogress.done()
}
