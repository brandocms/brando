// ***********************************************************
// This example support/index.js is processed and
// loaded automatically before your test files.
//
// This is a great place to put global configuration and
// behavior that modifies Cypress.
//
// You can change the location of this file or turn off
// automatically serving support files with the
// 'supportFile' configuration option.
//
// You can read more here:
// https://on.cypress.io/configuration
// ***********************************************************

// Import commands.js using ES2015 syntax:
import './commands'

before(() => {
  // Before we run any tests, we reset our database.
  // We also check back in any open database connection. If you save a
  // test file, cypress will re-run the tests, not finishing the ones it
  // is currently running, so we might end up with a checked-out connection
  // lying around and blocking our database reset.
  cy.checkindb()
})

beforeEach(() => {
  // Before each test, we check out a database connection
  cy.checkoutdb()
})

afterEach(() => {
  // After each test, we check the database connection back in
  cy.checkindb()
})