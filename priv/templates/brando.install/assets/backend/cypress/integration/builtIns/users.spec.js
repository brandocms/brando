describe('Users', () => {
  beforeEach(() => {
    cy.factorydb('user', { email: 'lou@reed.com', role: 'superuser' })
    cy.login('lou@reed.com', 'admin')
  })

  it('can visit profile from dropdown', () => {
    cy.visit('/admin')
    cy.get('#profile-dropdown-button').click()
    cy.get('a.dropdown-item').click()
    cy.location('pathname').should('eq', '/admin/profil')
  })

  it('can edit profile', () => {
    cy.visit('/admin/profil')
    cy.get('#profile_full_name_').clear().type('Lou Reed')
    cy.get('#profile_email_').clear().type('louis.reed@gmail.com')
    cy.get('#profile_password_').clear().type('password')
    cy.get('#profile_password_confirm_').clear().type('password')
    cy.get('[type="submit"]').click()
    cy.contains('Lagret profilinformasjon')
  })

  it('can list users', () => {
    cy.factorydb('user', { full_name: 'Iggy Pop', email: 'iggy@pop.com' })
    cy.factorydb('user', { full_name: 'David Bowie', email: 'david@bowie.com' })
    cy.visit('/admin/brukere')
    cy.contains('Iggy Pop')
    cy.contains('David Bowie')
  })

  it('can delete users', () => {
    cy.factorydb('user', { full_name: 'Iggy Pop', email: 'iggy@pop.com', role: 'admin' })
    cy.factorydb('user', { full_name: 'David Bowie', email: 'david@bowie.com' })
    cy.visit('/admin/brukere')
    cy.contains('Iggy Pop')
    cy.contains('David Bowie')

    cy.get('#__BVID__40__BV_toggle_').click()
    cy.get('#__BVID__40 > .dropdown-menu > :nth-child(1)').click()

    cy.contains('Brukeren ble deaktivert')

    cy.get('#__BVID__36__BV_toggle_').click()
    cy.get('#__BVID__36 > .dropdown-menu > :nth-child(1)').click()
    cy.contains('Brukeren er superbruker — kan ikke deaktiveres')
  })

  it('can add user', () => {
    cy.factorydb('user', { full_name: 'Iggy Pop', email: 'iggy@pop.com', role: 'admin' })
    cy.visit('/admin/brukere/ny')
    cy.contains('Ny bruker')

    cy.get(':nth-child(2) > .form-check-label > .form-check-input').click()
    cy.get('#user_full_name_').type('Ron Asheton')
    cy.get('#user_email_').type('ron@stooges.com')
    cy.get('#user_password_').type('password')
    cy.get('#user_password_confirm_').type('password')
    cy.get('.btn').click()

    cy.contains('La til ny bruker')

    cy.location('pathname').should('eq', '/admin/brukere')
    cy.contains('Ron Asheton')
  })
})
