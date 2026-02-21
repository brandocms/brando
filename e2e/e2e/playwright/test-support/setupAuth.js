// setup.js
import { test as baseTest, expect } from '@playwright/test'

export const test = baseTest.extend({
  // We put this placeholder here so that we can use it in the page fixture
  // In test files, we replace with the actual scenario name
  // via `test.use({ scenario: 'scenario-name' })`
  scenario: '',
  page: async ({ browser, scenario }, use) => {
    // IMPORTANT: Checkout sandbox FIRST to get the user-agent string
    // All subsequent requests must use this user-agent for sandbox isolation
    const sandboxResp = await fetch('http://localhost:4444/sandbox', {
      method: 'POST',
    })

    if (!sandboxResp.ok) {
      throw new Error(`Sandbox checkout failed: ${sandboxResp.status} ${await sandboxResp.text()}`)
    }

    const userAgentString = await sandboxResp.text()

    if (!userAgentString || !userAgentString.startsWith('BeamMetadata')) {
      throw new Error(`Invalid sandbox response: ${userAgentString}`)
    }

    // Login WITH the sandbox user-agent so the request uses the sandbox connection
    const authResponse = await fetch(
      'http://localhost:4444/e2e/login/admin@brandocms.com',
      {
        method: 'POST',
        headers: {
          'user-agent': userAgentString,
        },
      }
    )

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

    // Hide toast notifications so they don't intercept pointer events in tests
    await context.addInitScript(() => {
      const style = document.createElement('style')
      style.textContent = '.iziToast-wrapper { display: none !important; }'
      const inject = () => document.head?.appendChild(style.cloneNode(true))
      if (document.head) inject()
      else document.addEventListener('DOMContentLoaded', inject)
    })

    // page.request allows us to execute a HTTP call in the actual browser context
    // It's used for setting up fixtures in the database
    // and will also allow the created user to be logged in
    // via a cookie returned in the response
    // await page.request.post(`http://localhost:4444/e2e/setup_fixtures/${scenario}`, {
    //   headers: {
    //     'user-agent': userAgentString
    //   }
    // })

    try {
      await use(page)
    } finally {
      // Ensure sandbox is always cleaned up, even if the test fails.
      // Without this, failed tests leak sandbox connections, causing
      // cascading sandbox errors in subsequent tests.
      await fetch('http://localhost:4444/sandbox', {
        method: 'DELETE',
        headers: {
          'user-agent': userAgentString,
        },
      })
      await context.close()
    }
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
