// ***********************************************
// This example commands.js shows you how to
// create various custom commands and overwrite
// existing commands.
//
// For more comprehensive examples of custom
// commands please read more here:
// https://on.cypress.io/custom-commands
// ***********************************************

import 'cypress-file-upload'
import '../../../assets/backend/node_modules/brandojs/e2e/commands'

Cypress.Commands.add('checkoutdb', () => {
  cy.request('POST', '/__e2e/db/checkout').as('checkoutDb')
})

Cypress.Commands.add('checkindb', () => {
  cy.request('POST', '/__e2e/db/checkin').as('checkinDb')
})

Cypress.Commands.add('factorydb', (schema, attrs) => {
  cy.log(`Creating a ${schema} via fullstack factory`)
  cy.request('POST', '/__e2e/db/factory', {
    schema: schema,
    attributes: attrs
  }).as('factoryDb')
})

Cypress.Commands.add('login', (email, password) => {
  cy.request('POST', '/admin/auth/login', {
    email: email,
    password: password
  })
    .then(resp => {
      window.localStorage.setItem('token', resp.body.jwt)
    })
})

Cypress.Commands.add('loginUser', () => {
  cy
    .factorydb('user', { name: 'Lou Reed', avatar: null, email: 'lou@reed.com', role: 'superuser' })
    .as('currentUser')
    .then(response => {
      cy.login(response.body.email, 'admin')
    })
})
