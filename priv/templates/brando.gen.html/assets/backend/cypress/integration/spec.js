describe('<%= Recase.SentenceCase.convert(snake_domain) %>', () => {
  beforeEach(() => {
    cy.factorydb('user', { email: 'lou@reed.com', role: 'superuser' })
    cy.login('lou@reed.com', 'admin')
  })

  it('can list <%= Recase.SentenceCase.convert(plural) |> String.downcase() %>', () => {
    cy.factorydb('<%= singular %>', {})
    cy.visit('/admin/<%= plural %>')
    cy.location('pathname').should('eq', '/admin/<%= plural %>')
    cy.contains('Ny <%= vue_singular %>')
  })

  it('can create <%= Recase.SentenceCase.convert(plural) |> String.downcase() %>', () => {
    cy.visit('/admin/<%= plural %>')
    cy.contains('Ny <%= vue_singular %>').click()
    cy.location('pathname').should('eq', '/admin/<%= singular %>/ny')
    cy.contains('Lagre').click()
    cy.location('pathname').should('eq', '/admin/<%= plural %>')
  })

  it('can edit <%= Recase.SentenceCase.convert(plural) |> String.downcase() %>', () => {
    cy.factorydb('<%= singular %>', {})
    cy.visit('/admin/<%= plural %>')

    cy.get('tr > :nth-child(6) .dropdown').click()
    cy.contains('Endre').click()

    cy.location('pathname').should('match', /admin\/<%= singular %>\/endre\/(\d+)/)
    cy.contains('Endre')

    cy.contains('Lagre').click()

    cy.location('pathname').should('eq', '/admin/<%= plural %>')
  })

  it('can delete page', () => {
    cy.factorydb('<%= singular %>', {})
    cy.visit('/admin/<%= plural %>')

    cy.get('tr > :nth-child(6) .dropdown').click()
    cy.contains('Slett').click()
  })
})
