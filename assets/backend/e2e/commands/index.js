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

Cypress.Commands.add('defaultlanguage', () => {
  cy.log(`Getting default language`)
  cy.request('POST', '/__e2e/db/default_language').then(({ body }) => body).as('defaultLanguage')
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