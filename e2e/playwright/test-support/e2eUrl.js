const host = process.env.BRANDO_URL_HOST || 'localhost'
const port = process.env.BRANDO_E2E_PORT || process.env.PORT || '4444'

export const baseURL = (
  process.env.BRANDO_E2E_BASE_URL || `http://${host}:${port}`
).replace(/\/$/, '')

export const e2eUrl = (path) => new URL(path, `${baseURL}/`).toString()
