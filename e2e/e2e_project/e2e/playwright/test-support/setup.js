import { test as baseTest, expect } from '@playwright/test'

export const test = baseTest.extend({
  page: async ({ browser }, use) => {
    // This checks out the DB and gets the user agent string
    const resp = await fetch('http://localhost:4444/sandbox', {
      method: 'POST'
    })

    const userAgentString = await resp.text()

    // We setup a new browser context with the user agent string
    // This allows the database to be sandboxed and provides isolation
    const context = await browser.newContext({
      baseURL: 'http://localhost:4444',
      userAgent: userAgentString
    })

    const page = await context.newPage()

    try {
      await use(page)
    } finally {
      // Ensure cleanup happens even if test fails
      await fetch('http://localhost:4444/sandbox', {
        method: 'DELETE',
        headers: {
          'user-agent': userAgentString
        }
      })
      await context.close()
    }
  }
})

export { expect }
