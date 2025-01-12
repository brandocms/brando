// setup.js
import { test as baseTest, expect } from '@playwright/test'

export const test = baseTest.extend({
  // We put this placeholder here so that we can use it in the page fixture
  // In test files, we replace with the actual scenario name
  // via `test.use({ scenario: 'scenario-name' })`
  scenario: '',
  page: async ({ browser, scenario }, use) => {
    const authResponse = await fetch(
      'http://localhost:4444/e2e/login/admin@brandocms.com',
      {
        method: 'POST',
      }
    )

    // This checks out the DB and gets the user agent string
    const resp = await fetch('http://localhost:4444/sandbox', {
      method: 'POST',
    })

    const userAgentString = await resp.text()

    // We setup a new browser context with the user agent string
    // This allows the database to be sandboxed and provides isolation
    const context = await browser.newContext({
      baseURL: 'http://localhost:4444',
      userAgent: userAgentString,
    })

    // Extract and set cookies
    const setCookieHeader = authResponse.headers.get('set-cookie')

    if (setCookieHeader) {
      const cookies = parseSetCookieHeader(setCookieHeader)
      await context.addCookies(cookies)
    }

    const page = await context.newPage()

    // page.request allows us to execute a HTTP call in the actual browser context
    // It's used for setting up fixtures in the database
    // and will also allow the created user to be logged in
    // via a cookie returned in the response
    // await page.request.post(`http://localhost:4444/e2e/setup_fixtures/${scenario}`, {
    //   headers: {
    //     'user-agent': userAgentString
    //   }
    // })

    await use(page)

    await fetch('http://localhost:4444/sandbox', {
      method: 'DELETE',
      headers: {
        'user-agent': userAgentString,
      },
    })
  },
})

// Helper function to parse 'Set-Cookie' header
function parseSetCookieHeader(setCookieHeader) {
  const cookies = []
  const cookieHeaders = Array.isArray(setCookieHeader)
    ? setCookieHeader
    : [setCookieHeader]

  for (const header of cookieHeaders) {
    const cookie = {}
    const parts = header.split(';').map((part) => part.trim())

    // The first part is the name and value
    const [name, value] = parts[0].split('=')
    cookie.name = name
    cookie.value = value

    // Default values
    cookie.domain = 'localhost' // Adjust if your domain is different
    cookie.path = '/'
    cookie.expires = undefined
    cookie.httpOnly = false
    cookie.secure = false
    cookie.sameSite = 'Lax' // Default to 'Lax' if not specified

    // Parse additional attributes
    for (let i = 1; i < parts.length; i++) {
      const [attrName, attrValue] = parts[i].split('=')
      const lowerAttrName = attrName.toLowerCase()

      if (lowerAttrName === 'domain' && attrValue) {
        cookie.domain = attrValue
      } else if (lowerAttrName === 'path' && attrValue) {
        cookie.path = attrValue
      } else if (lowerAttrName === 'expires' && attrValue) {
        cookie.expires = new Date(attrValue).getTime()
      } else if (lowerAttrName === 'max-age' && attrValue) {
        cookie.expires = Date.now() + parseInt(attrValue, 10) * 1000
      } else if (lowerAttrName === 'httponly') {
        cookie.httpOnly = true
      } else if (lowerAttrName === 'secure') {
        cookie.secure = true
      } else if (lowerAttrName === 'samesite' && attrValue) {
        cookie.sameSite = attrValue
      }
    }

    cookies.push(cookie)
  }

  return cookies
}

export { expect }
