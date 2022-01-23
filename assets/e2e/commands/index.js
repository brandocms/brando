Cypress.Commands.add('checkoutdb', () => {
  cy.request('POST', '/__e2e/db/checkout').as('checkoutDb')
})

Cypress.Commands.add('checkindb', () => {
  cy.request('POST', '/__e2e/db/checkin').as('checkinDb')
})

Cypress.Commands.add('factorydb', (schema, attrs, currentUser) => {
  cy.log(`Creating a ${schema} via fullstack factory`)
  cy.request('POST', '/__e2e/db/factory', {
    schema: schema,
    attributes: attrs,
    creator_id: currentUser
  }).as('factoryDb')
})

Cypress.Commands.add('defaultlanguage', () => {
  cy.log(`Getting default language`)
  cy.request('POST', '/__e2e/db/default_language').then(({ body }) => body).as('defaultLanguage')
})


Cypress.Commands.add('login', (email, password) => {
  cy.request('/admin/login')
    .its('body')
    .then((body) => {
      // we can use Cypress.$ to parse the string body
      // thus enabling us to query into it easily
      const $html = Cypress.$(body)
      const csrf = $html.find('input[name=_csrf_token]').val()

      cy.loginByCSRF(csrf, email, password)
        .then((resp) => {
          expect(resp.status).to.eq(200)
          expect(resp.body).to.include('Dashboard')
        })
    })
})

Cypress.Commands.add('loginByCSRF', (csrfToken, email, password) => {
  cy.request({
    method: 'POST',
    url: '/admin/login',
    failOnStatusCode: false, // dont fail so we can make assertions
    form: true, // we are submitting a regular form body
    body: {
      user: {
        email,
        password
      },
      _csrf_token: csrfToken, // insert this as part of form body
    },
  })
})


Cypress.Commands.add('loginUser', () => {
  cy
    .factorydb('Brando.Users.User', { name: 'Lou Reed', avatar: null, email: 'lou@reed.com' })
    .as('currentUser')
    .then(response => {
      cy.login(response.body.email, 'admin')
    })
})