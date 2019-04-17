describe('Auth', () => {
  it('redirects to login page', () => {
    cy.visit('/admin/dashboard')
    cy.location('pathname').should('eq', '/admin/login')
  })

  it('has a sound login page', () => {
    cy.visit('/admin/login')
    cy.get('[data-cy-email]').should('exist')
    cy.get('[data-cy-password]').should('exist')
  })

  it('fails login for non-existing user', () => {
    cy.visit('/admin/login')
    cy.get('[data-cy-email]')
      .type('fake@email.com')
      .should('have.value', 'fake@email.com')

    cy.get('[data-cy-password]')
      .type('password')
      .should('have.value', 'password')

    cy.contains('Logg inn').click()

    cy.get('.vex-content').contains('Feil brukernavn eller passord')
  })

  it('fails logging in empty values', () => {
    cy.visit('/admin/login')
    cy.contains('Logg inn').click()
    cy.get('.vex-content').contains('Feil brukernavn eller passord')
  })

  it('succeeds logging in an existing user', () => {
    cy.factorydb('user', {
      email: 'lou@reed.com'
    })

    cy.visit('/admin/login')
    cy.get('[data-cy-email]')
      .type('lou@reed.com')
      .should('have.value', 'lou@reed.com')

    cy.get('[data-cy-password]')
      .type('admin')
      .should('have.value', 'admin')

    cy.contains('Logg inn').click()

    cy.location('pathname').should('eq', '/admin/')
    cy.contains('Administrasjonsområde')
    cy.contains('James Williamson')
    cy.contains('administrator')
    cy.get('.user-presence > .avatar > .rounded-circle').its('length').should('eq', 1)
  })

  it('can log out', () => {
    cy.factorydb('user', { email: 'lou@reed.com', role: 'superuser' })
    cy.login('lou@reed.com', 'admin')
    cy.get('#profile-dropdown-button').click()
    cy.contains('Logg ut').click()
    cy.location('pathname').should('eq', '/admin/login')
  })
})
