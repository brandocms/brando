// setup.js
import { test as baseTest, expect } from '@playwright/test'

// Log a user in and build a browser context bound to the given sandbox
// user-agent. Every context sharing the same user-agent shares the same
// per-test SQL sandbox session — this is what makes multi-user specs
// possible (see the `secondUserPage` fixture).
async function buildUserPage(browser, userAgentString, email) {
  const authResponse = await fetch(`http://localhost:4444/e2e/login/${email}`, {
    method: 'POST',
    headers: {
      'user-agent': userAgentString,
    },
  })

  const context = await browser.newContext({
    baseURL: 'http://localhost:4444',
    userAgent: userAgentString,
  })

  const setCookieHeader = authResponse.headers.get('set-cookie')

  if (setCookieHeader) {
    const cookies = parseSetCookieHeader(setCookieHeader)
    await context.addCookies(cookies)
  }

  // Hide toast notifications so they don't intercept pointer events in tests
  await context.addInitScript(() => {
    const style = document.createElement('style')
    style.textContent = '.iziToast-wrapper { display: none !important; }'
    const inject = () => document.head?.appendChild(style.cloneNode(true))
    if (document.head) inject()
    else document.addEventListener('DOMContentLoaded', inject)
  })

  const page = await context.newPage()
  return { context, page }
}

export const test = baseTest.extend({
  // We put this placeholder here so that we can use it in the page fixture
  // In test files, we replace with the actual scenario name
  // via `test.use({ scenario: 'scenario-name' })`
  scenario: '',

  // Per-test SQL sandbox session. All contexts created with this user-agent
  // share one sandbox transaction, rolled back at test end.
  sandboxUserAgent: async ({}, use) => {
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

    try {
      await use(userAgentString)
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
    }
  },

  page: async ({ browser, sandboxUserAgent, scenario }, use) => {
    const { context, page } = await buildUserPage(browser, sandboxUserAgent, 'admin@brandocms.com')

    try {
      await use(page)
    } finally {
      await context.close()
    }
  },

  // A SECOND logged-in user (seeded "editor@brandocms.com") sharing the same
  // sandbox session as `page` — for multi-user collaboration specs. Lazy:
  // only set up when a test declares it.
  secondUserPage: async ({ browser, sandboxUserAgent }, use) => {
    const { context, page } = await buildUserPage(browser, sandboxUserAgent, 'editor@brandocms.com')

    try {
      await use(page)
    } finally {
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
