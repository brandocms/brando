import { alertError } from './alerts'
import nprogress from 'nprogress'

export default function showError (err) {
  switch (err.code) {
    case '422':
      alertError('Valideringsfeil', err.error)
      break
    default:
      if (err.error) {
        alertError('Feil', err.error)
      } else {
        alertError('Ukjent feil', err.message)
      }
  }
  nprogress.done()
}
